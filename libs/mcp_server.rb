# frozen_string_literal: true

require 'json'
require_relative 'boot'

module Negromatic
  class McpServer
    def initialize
      @input = STDIN
      @output = STDOUT
    end

    def run
      while line = @input.gets
        begin
          request = JSON.parse(line)
          handle_request(request)
        rescue JSON::ParserError
          # Ignore invalid JSON
        end
      end
    end

    private

    def handle_request(request)
      method = request['method']
      params = request['params'] || {}
      id = request['id']

      case method
      when 'initialize'
        respond(id, {
          protocolVersion: '2024-11-05',
          capabilities: {
            tools: {
              listChanged: false
            }
          },
          serverInfo: {
            name: 'negromatic-server',
            version: '1.0.0'
          }
        })
      when 'tools/list'
        respond(id, {
          tools: [
            {
              name: 'send_message',
              description: 'Send a message to a contact via a specific channel (whatsapp, telegram, etc.)',
              inputSchema: {
                type: 'object',
                properties: {
                  channel_id: { type: 'integer' },
                  contact_id: { type: 'integer' },
                  content: { type: 'string' }
                },
                required: ['channel_id', 'contact_id', 'content']
              }
            },
            {
              name: 'notify_supervisor',
              description: 'Escalate a situation or report to the human supervisor',
              inputSchema: {
                type: 'object',
                properties: {
                  assistant_id: { type: 'integer' },
                  content: { type: 'string' }
                },
                required: ['assistant_id', 'content']
              }
            },
            {
              name: 'search_memory',
              description: 'Search for relevant facts in global or contact-specific memory',
              inputSchema: {
                type: 'object',
                properties: {
                  assistant_id: { type: 'integer' },
                  contact_id: { type: 'integer' },
                  query: { type: 'string' }
                },
                required: ['assistant_id', 'query']
              }
            },
            {
              name: 'generate_image',
              description: 'Generate an image based on a prompt for social media or messaging',
              inputSchema: {
                type: 'object',
                properties: {
                  prompt: { type: 'string' }
                },
                required: ['prompt']
              }
            },
            {
              name: 'schedule_task',
              description: 'Schedule a task to be executed later (e.g. follow up, post to social media)',
              inputSchema: {
                type: 'object',
                properties: {
                  assistant_id: { type: 'integer' },
                  task_type: { type: 'string', enum: ['follow_up', 'social_post'] },
                  payload: { type: 'object' },
                  run_at: { type: 'string', description: 'ISO8601 timestamp' }
                },
                required: ['assistant_id', 'task_type', 'run_at']
              }
            }
          ]
        })
      when 'tools/call'
        handle_tool_call(id, params['name'], params['arguments'])
      else
        respond_error(id, -32601, 'Method not found')
      end
    end

    def handle_tool_call(id, tool_name, args)
      result = case tool_name
               when 'send_message'
                 execute_send_message(args)
               when 'notify_supervisor'
                 execute_notify_supervisor(args)
               when 'search_memory'
                 execute_search_memory(args)
               when 'generate_image'
                 execute_generate_image(args)
               when 'schedule_task'
                 execute_schedule_task(args)
               else
                 { error: "Unknown tool: #{tool_name}" }
               end

      respond(id, { content: [{ type: 'text', text: result.to_json }] })
    end

    def execute_generate_image(args)
      url = AI.generate_image(args['prompt'])
      { success: !!url, url: url }
    rescue => e
      { success: false, error: e.message }
    end

    def execute_schedule_task(args)
      task = ScheduledTask.create!(
        assistant_id: args['assistant_id'],
        task_type: args['task_type'],
        payload: args['payload'] || {},
        run_at: args['run_at'],
        status: 'pending'
      )
      { success: true, task_id: task.id, message: "Task scheduled for #{args['run_at']}" }
    rescue => e
      { success: false, error: e.message }
    end

    def execute_send_message(args)
      channel = Channel.find(args['channel_id'])
      contact = Contact.find(args['contact_id'])
      
      provider_class = "Negromatic::Channels::#{channel.provider.camelize}".constantize
      client = provider_class.new(channel)
      
      success = client.send_message(contact, args['content'])
      { success: success }
    rescue => e
      { success: false, error: e.message }
    end

    def execute_notify_supervisor(args)
      assistant = Assistant.find(args['assistant_id'])
      success = assistant.notify_supervisor(args['content'])
      { success: success }
    rescue => e
      { success: false, error: e.message }
    end

    def execute_search_memory(args)
      memories = Memory.search(args['query'], 
        assistant_id: args['assistant_id'], 
        contact_id: args['contact_id']
      )
      { results: memories.map(&:content) }
    rescue => e
      { success: false, error: e.message }
    end

    def respond(id, result)
      @output.puts({
        jsonrpc: '2.0',
        id: id,
        result: result
      }.to_json)
      @output.flush
    end

    def respond_error(id, code, message)
      @output.puts({
        jsonrpc: '2.0',
        id: id,
        error: { code: code, message: message }
      }.to_json)
      @output.flush
    end
  end
end
