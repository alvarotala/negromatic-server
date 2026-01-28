class Contact < ActiveRecord::Base
  belongs_to :assistant
  has_many :interactions, dependent: :destroy

  has_many :identities, class_name: 'ContactIdentity', dependent: :destroy
  has_many :memories, dependent: :destroy
  # Also keep the interactions - we will re-link them on merge
  
  # Find or create a Unified Contact
  # 
  # logic:
  # 1. Look for a ContactIdentity matching (provider, external_id)
  #    -> If found, return its contact
  # 2. If not found, create new Contact and ContactIdentity
  
  def self.resolve(assistant, provider, external_id, profile_data = {})
    # 1. Search by Identity
    identity = ContactIdentity.find_by(assistant_id: assistant.id, provider: provider, external_id: external_id)
    if identity
      contact = identity.contact
      # Update profile data if given
      if profile_data.present?
        identity.update(profile_data: profile_data)
        # Maybe update contact name too if missing
        if contact.name.blank? && (name = profile_data['name'] || profile_data[:name])
          contact.update(name: name)
        end
      end
      return contact
    end

    # 2. Create New Contact
    contact = assistant.contacts.create!(
      name: profile_data['name'] || profile_data[:name],
      profile_data: profile_data
    )

    # Create the Identity linking back to this contact
    ContactIdentity.create!(
      contact: contact,
      assistant: assistant,
      provider: provider,
      external_id: external_id,
      profile_data: profile_data
    )

    contact
  end

  # Merge another contact into this one
  def merge(other_contact)
    return if other_contact.id == id

    ActiveRecord::Base.transaction do
      # 1. Move Identities
      other_contact.identities.update_all(contact_id: id)

      # 2. Move Interactions
      other_contact.interactions.update_all(contact_id: id)

      # 3. Move Memories
      other_contact.memories.update_all(contact_id: id)

      # 4. Merge Profile Data / Name if needed
      if name.blank? && other_contact.name.present?
        update(name: other_contact.name)
      end
      
      # Merge JSON profile data - shallow merge
      new_profile = (other_contact.profile_data || {}).merge(profile_data || {})
      update(profile_data: new_profile)

      # 5. Destroy the empty shell
      other_contact.destroy
    end
  end
end
