class House < ActiveRecord::Base
  has_many :rooms
  has_many :permits

	APPROVABLE_ASSOCIATIONS = %i(rooms)
	NULLIFY_ATTRIBUTES = %i(address)
end

class Room < ActiveRecord::Base
  belongs_to :house
  belongs_to :flooring_style
  has_many   :electrical_outlets
  has_many   :closets
  has_many   :trim_styles

	APPROVABLE_ASSOCIATIONS = %i(flooring_style closets trim_styles)
end

class Permit < ActiveRecord::Base
  belongs_to :house
end

class FlooringStyle < ActiveRecord::Base
  has_one :room
end

class ElectricalOutlet < ActiveRecord::Base
  belongs_to :room
end

class Closet < ActiveRecord::Base
  belongs_to :room
  attr_accessor :shape
end

class TrimStyle < ActiveRecord::Base
  belongs_to :room
  attr_accessor :style
end

class Apartment < ActiveRecord::Base
end