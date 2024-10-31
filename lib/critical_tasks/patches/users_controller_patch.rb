module CriticalTasks
  module Patches
    module UsersControllerPatch
      def self.included(base)
        base.class_eval do
          # Добавляем telegram_id в список разрешенных параметров
          before_action :add_telegram_id_to_allowed_params, only: [:update, :create]

          private

          def add_telegram_id_to_allowed_params
            return unless params[:user]
            params[:user].merge!(params.require(:user).permit(:telegram_id))
          end
        end
      end
    end
  end
end