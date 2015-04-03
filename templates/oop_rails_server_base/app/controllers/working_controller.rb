class WorkingController < ApplicationController
  def rails_is_working
    render :text => "Rails version: #{Rails.version}\nRuby version: #{RUBY_VERSION}\nRuby engine: #{RUBY_ENGINE}\n"
  end
end
