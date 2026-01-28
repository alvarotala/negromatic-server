module Negromatic
  module Tools
    class ManageContact
      def self.definition
        {
          type: 'function',
          function: {
            name: 'manage_contact',
            description: 'Manage contact identities and data.',
            parameters: {
              type: 'object',
              properties: {
                action: {
                  type: 'string',
                  enum: ['link_identity', 'update_profile', 'get_profile'],
                  description: 'The action to perform.'
                },
                provider: {
                  type: 'string',
                  description: 'The provider name (e.g., instagram, whatsapp). Required for link_identity.'
                },
                external_id: {
                  type: 'string',
                  description: 'The unique ID on the provider. Required for link_identity.'
                },
                data: {
                  type: 'object',
                  description: 'Key-value pairs to update. Standard keys: "name", "email", "notes", "memory" (for persistent long-term knowledge/bio). Required for update_profile.'
                }
              },
              required: ['action']
            }
          }
        }
      end

      def initialize(assistant, current_contact, current_channel)
        @assistant = assistant
        @current_contact = current_contact
        @current_channel = current_channel
      end

      def execute(args)
        case args['action']
        when 'link_identity'
          return "Error: provider and external_id are required for link_identity" unless args['provider'] && args['external_id']
          link_identity(args['provider'], args['external_id'])
        when 'update_profile'
          return "Error: data object is required for update_profile" unless args['data'].is_a?(Hash)
          update_profile(args['data'])
        when 'get_profile'
          get_profile
        else
          "Unknown action: #{args['action']}"
        end
      rescue => e
        "Error: #{e.message}"
      end

      private

      def get_profile
        {
          id: @current_contact.id,
          name: @current_contact.name,
          memory: @current_contact.memory,
          profile_data: @current_contact.profile_data,
          identities: @current_contact.identities.map { |i| { provider: i.provider, external_id: i.external_id } }
        }.to_json
      end

      def update_profile(data)
        # 1. Update direct fields if present
        if data['name']
          @current_contact.update(name: data['name'])
        end
        if data['memory']
          @current_contact.update(memory: data['memory'])
        end
        
        # 2. Merge profile_data
        current_data = @current_contact.profile_data || {}
        new_data = current_data.merge(data)
        
        if @current_contact.update(profile_data: new_data)
          "Contact profile updated successfully. Current data: #{new_data.inspect}"
        else
          "Failed to update profile: #{@current_contact.errors.full_messages.join(', ')}"
        end
      end

      def link_identity(provider, external_id)
        # 1. Search for existing identity
        identity = ContactIdentity.find_by(assistant_id: @assistant.id, provider: provider, external_id: external_id)

        if identity
          other_contact = identity.contact
          
          if other_contact.id == @current_contact.id
            return "Identity #{provider}/#{external_id} is already linked to this contact."
          else
            # Merge confirmed
            @current_contact.merge(other_contact)
            return "Successfully merged contacts. Found match on #{provider} (#{external_id}). All history is now combined."
          end
        else
          # 2. No existing identity found -> Just add identity to current contact
          @current_contact.identities.create!(
            assistant: @assistant,
            provider: provider,
            external_id: external_id
          )
          return "Linked new identity #{provider}/#{external_id} to this contact."
        end
      end
    end
  end
end
