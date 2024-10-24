RedmineApp::Application.routes.draw do
  get 'critical_tasks', to: 'critical_tasks#index'
end