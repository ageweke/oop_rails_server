class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery :with => :exception

  rescue_from Exception do |exception|
    render :json => {
      :exception => exception_to_hash(exception)
    }
  end

  private
  def exception_to_hash(exception)
    out = {
      :class => exception.class.name,
      :message => exception.message,
      :backtrace => exception.backtrace
    }

    if exception.respond_to?(:cause) && exception.cause && (! exception.cause.equal?(exception))
      out[:cause] = exception_to_hash(exception.cause)
    end

    out
  end
end
