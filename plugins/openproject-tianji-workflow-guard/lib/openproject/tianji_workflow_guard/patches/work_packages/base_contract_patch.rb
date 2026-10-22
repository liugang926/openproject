# frozen_string_literal: true
# Copyright (C) 2026 TianJi. SPDX-License-Identifier: GPL-3.0-only
module OpenProject
  module TianjiWorkflowGuard
    module Patches
      module WorkPackages
        module BaseContractPatch
          extend ActiveSupport::Concern
          included do
            validate :validate_tianji_managed_workflow
          end

          private

          def validate_tianji_managed_workflow
            ::OpenProject::TianjiWorkflowGuard::Runtime.validate(model:, user:)
          end
        end
      end
    end
  end
end
