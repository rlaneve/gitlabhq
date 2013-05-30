# == Schema Information
#
# Table name: services
#
#  id          :integer          not null, primary key
#  type        :string(255)
#  title       :string(255)
#  token       :string(255)
#  project_id  :integer          not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  active      :boolean          default(FALSE), not null
#  project_url :string(255)
#

class FlowdockService < Service
  validates :token, presence: true, if: :activated?

  def title
    'Flowdock'
  end

  def description
    'Team Inbox With Chat'
  end

  def to_param
    'flowdock'
  end

  def fields
    [
      { type: 'text', name: 'token',     placeholder: '' }
    ]
  end

  def execute(push_data)
    message = build_message(push_data)
  end

  private

  def build_message(push)
    ref = push[:ref].gsub("refs/heads/", "")
    before = push[:before]
    after = push[:after]

    message
  end
end
