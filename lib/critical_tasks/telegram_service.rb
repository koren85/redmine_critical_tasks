module CriticalTasks
  class TelegramService
    class << self
      def format_message(issues)
        Rails.logger.info "Formatting messages for #{issues.size} issues"

        template = message_template || default_message_template

        messages = []
        issues.each do |data|
          begin
            issue = data[:issue]
            problems = data[:problems]

            template_data = {
              issue_id: issue.id,
              subject: issue.subject,
              project: issue.project.name,
              status: issue.status.name,
              problems: format_problems(problems),
              url: generate_issue_url(issue)
            }

            formatted_message = template % template_data
            messages << formatted_message if formatted_message.present?
          rescue => e
            Rails.logger.error "Error formatting message for issue ##{issue&.id}: #{e.message}"
          end
        end

        final_message = messages.join("\n\n---\n\n")
        Rails.logger.info "Final message length: #{final_message.length} characters"

        final_message
      end

      def send_notification(telegram_id, message)
        return false unless telegram_enabled? && bot_token.present?
        return false if message.blank?

        begin
          Rails.logger.info "Sending message to: #{telegram_id}"

          # Форматируем chat_id (убираем @ если есть)
          chat_id = telegram_id.to_s.delete('@')

          # Экранируем специальные символы в сообщении
          escaped_message = message.gsub('"', '\"')

          # Формируем curl команду
          curl_command = %Q(curl -s -X POST "https://api.telegram.org/bot#{bot_token}/sendMessage" ) +
            %Q(-H "Content-Type: application/json" ) +
            %Q(-d "{\\"chat_id\\":\\"#{chat_id}\\",\\"text\\":\\"#{escaped_message}\\",\\"parse_mode\\":\\"HTML\\"}")

          Rails.logger.info "Executing curl command..."

          # Выполняем команду
          response = `#{curl_command}`
          result = JSON.parse(response)

          if result['ok']
            Rails.logger.info "Message sent successfully"
            true
          else
            Rails.logger.error "Telegram API error: #{result['description']}"
            false
          end
        rescue => e
          Rails.logger.error "Error sending notification: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          false
        end
      end

      def test_connection
        return false unless telegram_enabled? && bot_token.present?

        begin
          # Тестовый curl запрос к API
          curl_command = %Q(curl -s "https://api.telegram.org/bot#{bot_token}/getMe")
          response = `#{curl_command}`
          result = JSON.parse(response)

          if result['ok']
            bot_info = result['result']
            Rails.logger.info "Connected to bot: #{bot_info['username']}"
            true
          else
            Rails.logger.error "Bot connection failed: #{result['description']}"
            false
          end
        rescue => e
          Rails.logger.error "Error testing bot: #{e.message}"
          false
        end
      end

      private

      def message_template
        Setting.plugin_redmine_critical_tasks['telegram_message_template']
      end

      def default_message_template
        %{
Задача: #%{issue_id} - %{subject}
Проект: %{project}
Статус: %{status}
Проблемы: %{problems}
Ссылка: %{url}
        }.strip
      end

      def format_problems(problems)
        return "Нет проблем" if problems.blank?
        problems.join(", ")
      end

      def generate_issue_url(issue)
        host = Setting.host_name
        protocol = Setting.protocol || 'http'
        "#{protocol}://#{host}/issues/#{issue.id}"
      end

      def telegram_enabled?
        Setting.plugin_redmine_critical_tasks['telegram_enabled']
      end

      def bot_token
        Setting.plugin_redmine_critical_tasks['telegram_bot_token']
      end
    end
  end
end