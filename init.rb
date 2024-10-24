require 'redmine'
require 'rubyXL'
require 'rubyXL/convenience_methods'

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
    'error_date_past_color' => '#ffebee',    # светло-красный для просроченных дат
    'error_date_empty_color' => '#fff3e0',    # светло-оранжевый для пустых дат
  'color_opacity' => '0.8'  # Добавляем настройку прозрачности
  }, partial: 'settings/critical_tasks_settings'

  permission :view_critical_tasks, { critical_tasks: [:index] }

  menu :top_menu,
       :critical_tasks,
       { controller: 'critical_tasks', action: 'index' },
       caption: :critical_tasks_menu_caption,
       if: Proc.new { |p| User.current.allowed_to?(:view_critical_tasks, nil, global: true) }
end