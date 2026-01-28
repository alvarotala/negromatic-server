# frozen_string_literal: true

require 'json'
require 'ruby/openai'
require 'time'

# Provides a simple wrapper to query OpenAI compatible models (Grok)
module AI
  # Model options: 'grok-4', 'grok-4-1-fast-reasoning', 'grok-3', 'grok-3-mini'
  DEFAULT_MODEL = 'grok-4'
  DEFAULT_TEMPERATURE = 0.7

  API_KEY = ENV['GROK_API_KEY']
  BASE_URL = 'https://api.x.ai/v1'

  # Main entry point for chat interactions
  # messages: Array of message hashes [{ role: 'system', content: '...' }, ...]
  # tools: Array of tool definitions (optional)
  # Returns: { content: String|nil, tool_calls: Array|nil }
  def self.chat(messages, tools: [], model: DEFAULT_MODEL, temperature: DEFAULT_TEMPERATURE)
    client = OpenAI::Client.new(access_token: API_KEY, uri_base: BASE_URL)

    parameters = {
      model: model,
      messages: messages,
      temperature: temperature
    }

    if tools.any?
      parameters[:tools] = tools
      parameters[:tool_choice] = 'auto'
    end

    begin
      response = client.chat(parameters: parameters)

      message = response.dig('choices', 0, 'message')

      return { content: nil, tool_calls: nil } unless message

      result = {
        content: message['content'],
        tool_calls: message['tool_calls']
      }

      log(
        "AI Response: #{result[:content] ? result[:content][0..100] + '...' : 'nil'} | Tools: #{result[:tool_calls]&.count || 0}", level: :debug, color: :green
      )

      result
    rescue StandardError => e
      log("AI Chat Error: #{e.message}", level: :error, color: :red)
      { content: 'I encountered an error processing your request.', tool_calls: nil }
    end
  end

  # Asks the LLM to generate an image.
  def self.generate_image(prompt, model: 'grok-2-image-gen')
    log("AI Generating Image: #{prompt}", level: :debug, color: :cyan)
    client = OpenAI::Client.new(access_token: API_KEY, uri_base: BASE_URL)
    response = client.images.generate(
      parameters: {
        model: model,
        prompt: prompt,
        response_format: 'url'
      }
    )
    url = response.dig('data', 0, 'url')
    log("AI Image Generated: #{url}", level: :debug, color: :green)
    url
  rescue StandardError => e
    log("AI Image Generation Error: #{e.message}", level: :error, color: :red)
    nil
  end
end
