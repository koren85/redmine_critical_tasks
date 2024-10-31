module CriticalTasks
  module Hooks
    class ViewsUsersHook < Redmine::Hook::ViewListener
      def view_users_form_preferences(context = {})
        user = context[:user]
        form = context[:form]

        return '' unless user && form

        tag = '<p>'
        tag << "<label for='user_telegram_id'>#{l(:label_telegram_id)}</label>"
        tag << form.text_field(:telegram_id, size: 30)
        tag << "<em class='info'>#{l(:text_telegram_id_hint)}</em>"
        tag << '</p>'

        tag.html_safe
      end
    end
  end
end