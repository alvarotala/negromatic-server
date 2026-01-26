# frozen_string_literal: true

require 'logger'
require 'time'
require 'pastel'

# Lightweight global logger with optional colored output.
# - Uses Ruby's Logger (not puts)
# - Verbosity controlled by LOG_LEVEL (not APP_ENV)
module AppLogger
  def self.logger_level_from_env
    level = ENV.fetch('LOG_LEVEL', 'info').to_s.strip.downcase
    case level
    when 'debug' then Logger::DEBUG
    when 'info'  then Logger::INFO
    when 'warn'  then Logger::WARN
    when 'error' then Logger::ERROR
    when 'fatal' then Logger::FATAL
    else Logger::INFO
    end
  end

  def self.logger
    @logger ||= begin
      dest = $stdout
      l = Logger.new(dest)
      l.progname = 'tradero'
      l.level = logger_level_from_env
      l.formatter = proc do |severity, datetime, _progname, msg|
        "#{datetime.utc.iso8601} #{severity} #{msg}\n"
      end
      l
    end
  end

  # level: :debug, :info, :warn, :error, :fatal
  # color: Pastel method name (e.g., :cyan, :green, :yellow, :red)
  def self.log(message, level: :info, color: nil)
    msg = message.to_s

    if color && ($stdout.tty? || ENV['FORCE_COLOR_LOGS'])
      pastel = Pastel.new
      msg = pastel.public_send(color, msg)
    end

    severity = case level
               when :debug then Logger::DEBUG
               when :info then Logger::INFO
               when :warn then Logger::WARN
               when :error then Logger::ERROR
               when :fatal then Logger::FATAL
               else Logger::INFO
               end

    logger.add(severity, msg)
  rescue StandardError
    # Never let logging crash the app.
    logger.add(Logger::INFO, message.to_s)
  end
end

# Global helper: call `log("message", level: :info, color: :cyan)`
module Kernel
  def log(message, level: :info, color: nil)
    AppLogger.log(message, level: level, color: color)
  end
end

