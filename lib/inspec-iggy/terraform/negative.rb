# returns negative of Terraform tfstate file coverage

require 'hashie'

require "inspec/objects/control"
require "inspec/objects/ruby_helper"
require "inspec/objects/describe"

require "inspec-iggy/file_helper"
require "inspec-iggy/inspec_helper"
require "inspec-iggy/terraform/generate"

module InspecPlugins::Iggy::Terraform
  class Negative
    # parse through the JSON and generate InSpec controls
    def self.parse_negative(tf_file, resource_path, platform)
      tfstate = InspecPlugins::Iggy::FileHelper.parse_json(tf_file)
      sourcefile = File.absolute_path(tf_file)

      # take those Terraform resources and map to InSpec resources by name and keep all attributes
      parsed_resources = InspecPlugins::Iggy::Terraform::Generate.parse_resources(tfstate, resource_path, platform)

      # subtract matched resources from all available resources
      negative_controls = parse_unmatched_resources(parsed_resources, sourcefile, platform)
      negative_controls += parse_matched_resources(parsed_resources, sourcefile, platform)

      negative_controls
    end

    # return controls for the iterators of things unmatched in the terraform.tfstate
    def self.parse_unmatched_resources(resources, sourcefile, platform)
      resources.extend Hashie::Extensions::DeepFind # use to find iterators' values from other attributes
      unmatched_resources = InspecPlugins::Iggy::InspecHelper.available_resource_iterators(platform).keys - resources.keys
      Inspec::Log.debug "Terraform::Negative.parse_unmatched_resources unmatched_resources #{unmatched_resources}"
      unmatched_controls = []
      unmatched_resources.each do |unmatched|
        unresources = InspecPlugins::Iggy::InspecHelper.available_resource_iterators(platform)[unmatched]
        iterator = unresources["iterator"]
        ctrl = Inspec::Control.new
        ctrl.id = "NEGATIVE-COVERAGE:#{iterator}"
        ctrl.title = "InSpec-Iggy NEGATIVE-COVERAGE:#{iterator}"
        ctrl.descriptions[:default] = "NEGATIVE-COVERAGE:#{iterator} from the source file #{sourcefile}\nGenerated by InSpec-Iggy v#{InspecPlugins::Iggy::VERSION}"
        ctrl.impact = "1.0"
        describe = Inspec::Describe.new
        qualifier = [iterator, {}]
        unresources["qualifiers"].each do |parameter|
          Inspec::Log.debug "Terraform::Negative.parse_unmatched_resources #{iterator} qualifier found = #{parameter} MATCHED"
          value = resources.deep_find(parameter.to_s) # value comes from another likely source. Assumption is values are consistent for this type of field
          qualifier[1][parameter] = value
        end
        describe.qualifier.push(qualifier)
        describe.add_test(nil, "exist", nil, { negated: true }) # last field is negated
        ctrl.add_test(describe)
        unmatched_controls.push(ctrl)
      end
      Inspec::Log.debug "Terraform::Negative.parse_unmatched_resources negative_controls = #{unmatched_controls}"
      unmatched_controls
    end

    # controls for iterators minus the matched resources
    def self.parse_matched_resources(resources, sourcefile, platform) # rubocop:disable Metrics/AbcSize
      Inspec::Log.debug "Terraform::Negative.parse_matched_resources matched_resources #{resources.keys}"
      matched_controls = []
      resources.keys.each do |resource|
        resources[resource].extend Hashie::Extensions::DeepFind # use to find iterators' values from other attributes
        resource_iterators = InspecPlugins::Iggy::InspecHelper.available_resource_iterators(platform)[resource]
        if resource_iterators.nil?
          Inspec::Log.warn "No iterator matching #{resource} for #{platform} found!"
          next
        else
          iterator = resource_iterators["iterator"]
          index = resource_iterators["index"]
          Inspec::Log.debug "Terraform::Negative.parse_matched_resources iterator:#{iterator} index:#{index}"
        end
        # Nothing but the finest bespoke hand-built InSpec
        ctrl =  "control 'NEGATIVE-COVERAGE:#{iterator}' do\n"
        ctrl += "  title 'InSpec-Iggy NEGATIVE-COVERAGE:#{iterator}'\n"
        ctrl += "  desc \"\n"
        ctrl += "    NEGATIVE-COVERAGE:#{iterator} from the source file #{sourcefile}\n\n"
        ctrl += "    Generated by InSpec-Iggy v#{InspecPlugins::Iggy::VERSION}\"\n\n"
        ctrl += "  impact 1.0\n"
        # get the qualifiers for the resource iterator
        ctrl += "  (#{iterator}.where({ "
        if resource_iterators["qualifiers"]
          resource_iterators["qualifiers"].each do |parameter|
            Inspec::Log.debug "Terraform::Negative.parse_matched_resources #{iterator} qualifier found = #{parameter} MATCHED"
            value = resources[resource].deep_find(parameter.to_s) # value comes from resources being evaluated. Assumption is values are consistent for this type of field
            unless value
              Inspec::Log.warn "Terraform::Negative.parse_matched_resources #{resource} no #{parameter} value found, searching outside scope."
              value = resources.deep_find(parameter.to_s)
            end
            ctrl += "#{parameter}: '#{value}', "
          end
        end
        ctrl += "}).#{index} - [\n"
        # iterate over the resources
        resources[resource].keys.each do |resource_name|
          ctrl += "    '#{resource_name}',\n"
        end
        ctrl += "  ]).each do |id|\n"
        ctrl += "    describe #{resource}({ "
        # iterate over resource qualifiers
        first = true
        InspecPlugins::Iggy::InspecHelper.available_resource_qualifiers(platform)[resource].each do |parameter|
          if first # index is first
            ctrl += "#{parameter.to_s}: id, "
            first = false
            next
          end
          property = parameter.to_s
          properties = InspecPlugins::Iggy::InspecHelper.available_translated_resource_properties(platform, resource)
          if properties && properties.has_value?(parameter.to_s)
            property = properties.key(parameter.to_s) #translate back if necessary
          end
          # instead of looking up the key, find by value?
          Inspec::Log.debug "Iggy::Terraform::Negative.parse_matched_resources #{resource} qualifier found = #{property} MATCHED"
          value = resources[resource].deep_find(property) # value comes from resources being evaluated. Assumption is values are consistent for this type of field
          ctrl += "#{property}: '#{value}', "
        end
        ctrl += "}) do\n"
        ctrl += "      it { should_not exist }\n"
        ctrl += "    end\n"
        ctrl += "  end\n"
        ctrl += "end\n\n"
        matched_controls.push(ctrl)
      end
      Inspec::Log.debug "Terraform::Negative.parse_matched_resources negative_controls = #{matched_controls}"
      matched_controls
    end
  end
end
