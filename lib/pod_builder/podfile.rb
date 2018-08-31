require 'pod_builder/cocoapods/analyzer'

module PodBuilder
  class Podfile
    PODBUILDER_LOCK_ACTION = ["raise \"\\n🚨  Do not launch 'pod install' manually, use `pod_builder` instead!\\n\" if !File.exist?('pod_builder.lock')"].freeze    
    POST_INSTALL_ACTIONS = ["require 'pod_builder/podfile/post_actions'", "PodBuilder::Podfile::remove_target_support_duplicate_entries", "PodBuilder::Podfile::check_target_support_resource_collisions"].freeze
    
    PRE_INSTALL_ACTIONS = ["Pod::Installer::Xcode::TargetValidator.send(:define_method, :verify_no_duplicate_framework_and_library_names) {}"].freeze
    private_constant :PRE_INSTALL_ACTIONS

    def self.from_podfile_items(items, analyzer)
      raise "no items" unless items.count > 0

      sources = analyzer.sources
      
      cwd = File.dirname(File.expand_path(__FILE__))
      podfile = File.read("#{cwd}/templates/build_podfile.template")
      
      podfile.sub!("%%%sources%%%", sources.map { |x| "source '#{x.url}'" }.join("\n"))

      build_configurations = items.map(&:build_configuration).uniq
      raise "Found different build configurations in #{items}" if build_configurations.count != 1
      podfile.sub!("%%%build_configuration%%%", build_configurations.first.capitalize)

      podfile_build_settings = ""
      
      pod_dependencies = {}

      items.each do |item|
        build_settings = Configuration.build_settings.dup

        item_build_settings = Configuration.build_settings_overrides[item.name] || {}
        build_settings['SWIFT_VERSION'] = item_build_settings["SWIFT_VERSION"] || project_swift_version(analyzer)
        if item.is_static
          # https://forums.developer.apple.com/thread/17921
          build_settings['CLANG_ENABLE_MODULE_DEBUGGING'] = "NO"
        end

        item_build_settings.each do |k, v|
          build_settings[k] = v
        end

        podfile_build_settings += "set_build_settings(\"#{item.root_name}\", #{build_settings.to_s}, installer)\n  "

        dependency_names = item.dependency_names.map { |x|
          if x.split("/").first == item.root_name
            next nil # remove dependency to parent spec
          end
          if overridded_module_name = Configuration.spec_overrides.fetch(x, {})["module_name"]
            next overridded_module_name
          end
        }.compact
  
        if dependency_names.count > 0
          pod_dependencies[item.root_name] = dependency_names
        end
      end

      podfile.sub!("%%%build_settings%%%", podfile_build_settings)

      podfile.sub!("%%%build_system%%%", Configuration.build_system)

      podfile.sub!("%%%pods%%%", "\"#{items.map(&:name).join('", "')}\"")
      
      podfile.sub!("%%%pods_dependencies%%%", pod_dependencies.to_s)
      
      podfile.sub!("%%%targets%%%", items.map(&:entry).join("\n  "))

      return podfile
    end

    def self.write_restorable(updated_pods, podfile_items, analyzer)
      podfile_items = podfile_items.dup
      podfile_restore_path = PodBuilder::basepath("Podfile.restore")
      podfile_path = PodBuilder::basepath("Podfile")

      if File.exist?(podfile_restore_path)
        restore_podfile_items = podfile_items_at(podfile_restore_path)

        podfile_items.map! { |podfile_item|
          if updated_pod = updated_pods.detect { |x| x.name == podfile_item.name } then
            updated_pod
          elsif updated_pods.any? { |x| podfile_item.root_name == x.root_name } == false && # podfile_item shouldn't be among those being updated (including root specification)
                restored_pod = restore_podfile_items.detect { |x| x.name == podfile_item.name }
            restored_pod
          else
            podfile_item
          end
        }
      end

      result_targets = analyzer.result.targets.map(&:name) 
      podfile_content = analyzer.podfile.sources.map { |x| "source '#{x}'" }
      podfile_content += ["", "use_frameworks!", ""]

      # multiple platforms not (yet) supported
      # https://github.com/CocoaPods/Rome/issues/37
      platform = analyzer.result.targets.first.platform
      podfile_content += ["platform :#{platform.name}, '#{platform.deployment_target.version}'", ""]

      analyzer.result.specs_by_target.each do |target, specifications|
        unless result_targets.select { |x| x.end_with?(target.name) }.count > 0
          next
        end

        podfile_content.push("target '#{target.name}' do")

        specifications.each do |spec|
          item = podfile_items.detect { |x| x.name == spec.name }
          podfile_content.push("\t#{item.entry}")
        end

        podfile_content.push("end\n")
      end

      File.write(podfile_restore_path, podfile_content.join("\n"))
    end

    def self.write_prebuilt(all_buildable_items, analyzer)      
      podbuilder_podfile_path = PodBuilder::basepath("Podfile")
      rel_path = Pathname.new(podbuilder_podfile_path).relative_path_from(Pathname.new(PodBuilder::project_path)).to_s
    
      frameworks_base_path = PodBuilder::basepath("Rome")
    
      podfile_content = File.read(podbuilder_podfile_path)

      exclude_lines = Podfile::PODBUILDER_LOCK_ACTION.map { |x| Podfile.strip_line(x) }

      prebuilt_lines = ["# Autogenerated by PodBuilder (https://github.com/Subito-it/PodBuilder)\n", "# Any change to this file should be done on #{rel_path}\n", "\n"]
      podfile_content.each_line do |line|
        stripped_line = strip_line(line)

        if pod_name = pod_definition_in(line, true)
          if podfile_item = all_buildable_items.detect { |x| x.name == pod_name }
            if File.exist?("#{frameworks_base_path}/#{podfile_item.prebuilt_rel_path}")
              line = "#{line.detect_indentation}#{podfile_item.prebuilt_entry}\n"
            end
          end
        end

        if !exclude_lines.include?(stripped_line)
          prebuilt_lines.push(line)
        end
      end

      project_podfile_path = PodBuilder::project_path("Podfile")
      File.write(project_podfile_path, prebuilt_lines.join)

      add_pre_install_actions(project_podfile_path)
      add_post_install_checks(project_podfile_path)
    end

    def self.deintegrate_install
      current_dir = Dir.pwd

      Dir.chdir(PodBuilder::project_path)
      system("pod deintegrate; pod install;")
      Dir.chdir(current_dir)
    end

    def self.strip_line(line)
      stripped_line = line.dup
      return stripped_line.gsub("\"", "'").gsub(" ", "").gsub("\n", "")
    end

    def self.add_install_block(podfile_path)
      add(PODBUILDER_LOCK_ACTION, "pre_install", podfile_path)
    end

    def self.pod_definition_in(line, include_commented)
      stripped_line = strip_line(line)
      matches = stripped_line.match(/(^pod')(.*?)(')/)
      
      if matches&.size == 4 && (include_commented || !stripped_line.start_with?("#"))
        return matches[2]
      else
        return nil
      end
    end

    private
    
    def self.indentation_from_file(path)
      content = File.read(path)

      lines = content.split("\n").select { |x| !x.empty? }

      if lines.count > 2
        lines[0..-2].each_with_index do |current_line, index|
          next_line = lines[index + 1]
          next_line_first_char = next_line.chars.first
          current_doesnt_begin_with_whitespace = current_line[/\A\S*/] != nil

          if current_doesnt_begin_with_whitespace && [" ", "\t"].include?(next_line_first_char)
            return next_line[/\A\s*/]
          end          
        end
      end

      return "  "
    end

    def self.project_swift_version(analyzer)
      swift_versions = analyzer.result.target_inspections.values.map { |x| x.target_definition.swift_version }.compact.uniq

      raise "Found different Swift versions in targets. Expecting one, got `#{swift_versions}`" if swift_versions.count != 1

      return swift_versions.first
    end

    def self.podfile_items_at(podfile_path)
      raise "Expecting basepath folder!" if !File.exist?(PodBuilder::basepath("Podfile"))

      if File.basename(podfile_path) != "Podfile"
        File.rename(PodBuilder::basepath("Podfile"), PodBuilder::basepath("Podfile.tmp"))
        FileUtils.cp(podfile_path, PodBuilder::basepath("Podfile"))
      end

      current_dir = Dir.pwd
      Dir.chdir(File.dirname(podfile_path))

      buildable_items = []
      begin
        installer, analyzer = Analyze.installer_at(PodBuilder::basepath)
      
        podfile_items = Analyze.podfile_items(installer, analyzer)
        buildable_items = podfile_items.select { |item| !item.is_prebuilt }   
      rescue Exception => e
        raise e
      ensure
        Dir.chdir(current_dir)
      
        if File.basename(podfile_path) != "Podfile"
          File.rename(PodBuilder::basepath("Podfile.tmp"), PodBuilder::basepath("Podfile"))
        end  
      end

      return buildable_items
    end

    def self.add_pre_install_actions(podfile_path)
      add(PRE_INSTALL_ACTIONS + [" "], "pre_install", podfile_path)
    end

    def self.add_post_install_checks(podfile_path)
      add(POST_INSTALL_ACTIONS + [" "], "post_install", podfile_path)
    end

    def self.add(entries, marker, podfile_path)
      podfile_content = File.read(podfile_path)

      file_indentation = indentation_from_file(podfile_path)

      entries = entries.map { |x| "#{file_indentation}#{x}\n"}

      marker_found = false
      podfile_lines = []
      podfile_content.each_line do |line|
        stripped_line = Podfile::strip_line(line)

        podfile_lines.push(line)
        if stripped_line.start_with?("#{marker}do|")
          marker_found = true
          podfile_lines.push(entries)
        end
      end

      if !marker_found
        podfile_lines.push("\n#{marker} do |installer|\n")
        podfile_lines.push(entries)
        podfile_lines.push("end\n")
      end

      File.write(podfile_path, podfile_lines.join)
    end
  end
end
