module CriticalTasks
  module Patches
    module UserPatch
      def self.included(base)
        base.class_eval do
          safe_attributes 'telegram_id'

          # Изменяем валидацию, чтобы принимать как числовой ID, так и username
          validates :telegram_id,
                    format: {
                      with: /\A(?:\d+|@[a-zA-Z0-9_]{5,32})\z/,
                      message: :invalid_telegram_id
                    },
                    allow_blank: true

          def telegram_configured?
            telegram_id.present?
          end
        end
      end
    end
  end
end
unless User.included_modules.include?(CriticalTasks::Patches::UserPatch)
  User.include CriticalTasks::Patches::UserPatch
end