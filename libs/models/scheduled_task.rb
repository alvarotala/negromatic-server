# frozen_string_literal: true

class ScheduledTask < ActiveRecord::Base
  belongs_to :assistant

  validates :task_type, presence: true
  validates :run_at, presence: true
  
  scope :pending, -> { where(status: 'pending') }
  scope :due, -> { pending.where('run_at <= ?', Time.now) }
end
