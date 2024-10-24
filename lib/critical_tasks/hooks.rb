module CriticalTasks
  class Hooks < Redmine::Hook::ViewListener
    def view_layouts_base_html_head(context)
      stylesheet_link_tag('critical_tasks', plugin: 'redmine_critical_tasks') +
        javascript_include_tag('critical_tasks', plugin: 'redmine_critical_tasks')
    end
  end
end