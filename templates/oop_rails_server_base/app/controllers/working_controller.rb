class WorkingController < ApplicationController
  def rails_is_working
    engine = if defined?(RUBY_ENGINE) then RUBY_ENGINE else nil end
    render :text => "Rails version: #{Rails.version}\nRuby version: #{RUBY_VERSION}\nRuby engine: #{engine}\n"
  end
end
