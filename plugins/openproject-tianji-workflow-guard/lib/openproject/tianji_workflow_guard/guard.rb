# frozen_string_literal: true
# Copyright (C) 2026 TianJi. SPDX-License-Identifier: GPL-3.0-only
module OpenProject
  module TianjiWorkflowGuard
    class Guard
      def initialize(config)
        @authority = RailsAuthority.new(config)
        @policy = Policy.new(config)
      end

      def validate(model:, user:)
        return true unless @authority.managed_candidate?(model)

        code = @policy.evaluate(@authority.capture(model:, user:))
        return true if code.nil?

        deny(model, code)
      rescue StandardError
        # Never emit upstream messages, work package values, personal data or secrets.
        deny(model, :authority_unavailable)
      end

      private

      def deny(model, code)
        model.errors.add(:base, :tianji_workflow_guard_denied,
                         message: "Managed workflow write refused (#{code}).")
        false
      end
    end

    module Runtime
      class << self
        def boot!(config_path:, app_root:)
          compatibility = JSON.parse(File.binread(File.expand_path("../../../config/compatibility.json", __dir__)))
          compatibility.fetch("source_files").each do |relative, expected|
            raise ConfigurationError, "UPSTREAM_SOURCE_MISMATCH" unless Digest::SHA256.file(File.join(app_root, relative)).hexdigest == expected
          end
          version = ::OpenProject::VERSION.to_semver
          raise ConfigurationError, "UPSTREAM_VERSION_MISMATCH" unless version == "17.9.2"

          config = Config.load(config_path)
          @guard = Guard.new(config)
          @config_revision = config.revision
          verify_hooks!
        end

        def validate(model:, user:)
          raise ConfigurationError, "GUARD_NOT_BOOTED" unless @guard

          @guard.validate(model:, user:)
        end

        def verify_hooks!
          callbacks = ::WorkPackages::BaseContract._validate_callbacks.map(&:filter)
          raise ConfigurationError, "CONTRACT_HOOK_MISSING" unless callbacks.include?(:validate_tianji_managed_workflow)
          mod = ::OpenProject::TianjiWorkflowGuard::Patches::WorkPackages::DependentValidation
          raise ConfigurationError, "DEPENDENT_HOOK_MISSING" unless ::WorkPackages::UpdateDependentContract.ancestors.include?(mod)

          true
        end

        attr_reader :config_revision
      end
    end
  end
end
