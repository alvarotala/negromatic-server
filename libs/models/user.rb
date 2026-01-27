# frozen_string_literal: true

require 'bcrypt'

class User < ActiveRecord::Base
  include BCrypt
  has_many :assistants, dependent: :destroy

  # Comprehensive statistics
  # Returns a hash with all key metrics for dashboard display
  def stats
    {
      assistants_count: assistants.count,
      active_channels: Channel.where(assistant_id: assistants.pluck(:id), active: true).count,
      total_interactions: Interaction.where(assistant_id: assistants.pluck(:id)).count,
      total_contacts: Contact.where(assistant_id: assistants.pluck(:id)).count
    }
  end

  def reset_ai_history!
    # To be implemented for assistants if needed
  end

  # Hash password before saving if it has changed
  def password
    @password ||= Password.new(read_attribute(:password)) if read_attribute(:password).present?
  end

  def password=(new_password)
    @password = Password.create(new_password)
    write_attribute(:password, @password)
  end

  def self.authenticate(email, password)
    user = find_by(email: email)
    return user if user && user.password == password
    nil
  end
end
