class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery :with => :exception

  rescue_from Exception do |exception|
    if exception.respond_to?(:cause) && e = exception.cause
      exception = e
    end
    render :json => {
      :exception => {
        :class => exception.class.name,
        :message => exception.message,
        :backtrace => exception.backtrace
      }
    }
  end
end
