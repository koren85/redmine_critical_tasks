RedmineApp::Application.routes.draw do
  get 'critical_tasks', to: 'critical_tasks#index'
  resources :critical_tasks, only: [:index] do
    collection do
      post 'notify_responsible'
    end
  end
end
