module CriticalTasks
  class ViewHooks < Redmine::Hook::ViewListener

    def view_layouts_base_html_head(context={})
      return '' unless context[:controller] && context[:controller].is_a?(CriticalTasksController)
      stylesheet_link_tag('critical_tasks', plugin: 'redmine_critical_tasks') +
        javascript_include_tag('critical_tasks', plugin: 'redmine_critical_tasks')
    end
  end
end