require 'redmine'
require 'rubyXL'
require 'rubyXL/convenience_methods'

require 'critical_tasks/patches/user_patch'
require 'critical_tasks/telegram_service'
require 'critical_tasks/hooks/views_layouts_hook'
require 'critical_tasks/patches/users_controller_patch'
require 'critical_tasks/hooks/views_users_hook'

unless UsersController.included_modules.include?(CriticalTasks::Patches::UsersControllerPatch)
  UsersController.include CriticalTasks::Patches::UsersControllerPatch
end

# Регистрируем MIME тип для xlsx
Mime::Type.register "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", :xlsx

Redmine::Plugin.register :redmine_critical_tasks do
  name 'Critical Tasks Plugin'
  author 'Your Name'
  description 'Plugin for managing critical tasks with custom filtering'
  version '1.0.0'

  class RubyXL::Worksheet
    def add_autofilter(range)
      self.auto_filter ||= RubyXL::AutoFilter.new
      self.auto_filter.ref = range
    end
  end

  settings partial: 'settings/critical_tasks_settings'

  # Добавляем настройки по умолчанию для цветов
  settings default: {
    'custom_field_id' => nil,
    'parent_task_color' => '#f0f0f0',
    'subtask_color' => '#fafafa',
    'error_date_past_color' => '#ffebee', # светло-красный для просроченных дат
    'error_date_empty_color' => '#fff3e0', # светло-оранжевый для пустых дат
    'color_opacity' => '0.8', # Добавляем настройку прозрачности

    'telegram_bot_token' => nil,
    'telegram_enabled' => false,
    'telegram_message_template' => %{
Задача: #%{issue_id} - %{subject}
Проект: %{project}
Статус: %{status}
Проблемы: %{problems}
Ссылка: %{url}
    }.strip,
    'responsible_custom_field_id' => nil # ID кастомного поля для ответственного
  }, partial: 'settings/critical_tasks_settings'

  project_module :critical_tasks do
    permission :view_critical_tasks, { critical_tasks: [:index] }
    # Добавляем права для управления Telegram ID
    permission :manage_telegram_id, { users: [:edit_telegram_id, :update_telegram_id] }
    permission :send_telegram_notifications, { critical_tasks: [:notify_responsible] }
  end
  menu :top_menu,
       :critical_tasks,
       { controller: 'critical_tasks', action: 'index' },
       caption: :critical_tasks_menu_caption,
       if: Proc.new { |p| User.current.allowed_to?(:view_critical_tasks, nil, global: true) }

end