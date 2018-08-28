module PORO
  class DB
    class << self
      def data
        @data ||=
          {
            employees: [],
            positions: [],
            departments: [],
            classifications: [],
            bios: [],
            team_memberships: [],
            teams: [],
            visas: [],
            mastercards: [],
            visa_rewards: [],
            books: [],
            states: []
          }
      end

      def clear
        data.each_pair do |key, value|
          data[key] = []
        end
      end

      def klasses
        {
          employees: PORO::Employee,
          positions: PORO::Position,
          departments: PORO::Department,
          classifications: PORO::Classification,
          bios: PORO::Bio,
          teams: PORO::Team,
          visas: PORO::Visa,
          mastercards: PORO::Mastercard,
          visa_rewards: PORO::VisaReward,
          books: PORO::Book,
          states: PORO::State
        }
      end

      def all(params)
        type = params[:type]
        records = data.select { |k,v| Array(type).include?(k) }
        return [] unless records
        records = records.map do |type, _records|
          _records.map { |attrs| klasses[type].new(attrs) }
        end.flatten
        records = apply_filtering(records, params)
        records = apply_sorting(records, params)
        records = apply_pagination(records, params)
        records
      end

      private

      # TODO: the integer casting here should go away with attribute types
      def apply_filtering(records, params)
        return records unless params[:conditions]
        records.select! do |record|
          params[:conditions].all? do |key, value|
            db_value = record.send(key) if record.respond_to?(key)
            if key == :id
              value = value.is_a?(Array) ? value.map(&:to_i) : value.to_i
            end
            if value.is_a?(Array)
              value.include?(db_value)
            else
              db_value == value
            end
          end
        end
        records
      end

      def apply_sorting(records, params)
        return records if params[:sort].nil?

        params[:sort].reverse.each do |sort|
          records.sort! do |a, b|
            att = sort.keys[0]
            a.send(att) <=> b.send(att)
          end
          records = records.reverse if sort.values[0] == :desc
        end
        records
      end

      def apply_pagination(records, params)
        return records unless params[:per]

        start_at = (params[:page]-1)*(params[:per])
        end_at = (params[:page] * params[:per]) -1
        return [] if end_at < 0
        records[start_at..end_at]
      end
    end
  end

  class Base
    include ActiveModel::Validations
    attr_accessor :id

    def self.create(attrs = {})
      if (record = new(attrs)).valid?
        id = attrs[:id] || DB.data[type].length + 1
        attrs.merge!(id: id)
        record.id = id
        DB.data[type] << attrs
        record
      else
        record
      end
    end

    def self.type
      name.underscore.pluralize.split('/').last.to_sym
    end

    def initialize(attrs = {})
      attrs.each_pair { |k,v| send(:"#{k}=", v) }
    end

    def update_attributes(attrs)
      record = DB.data[self.class.type].find { |r| r[:id] == id }
      record.merge!(attrs)
    end
  end

  class Employee < Base
    attr_accessor :first_name,
      :last_name,
      :age,
      :active,
      :positions,
      :current_position,
      :bio,
      :teams,
      :classification,
      :classification_id,
      :credit_card,
      :credit_card_id,
      :cc_id,
      :credit_card_type

    def initialize(*)
      super
      @positions ||= []
      @teams ||= []
    end
  end

  class Position < Base
    attr_accessor :title,
      :rank,
      :employee_id,
      :e_id,
      :employee,
      :department_id,
      :department
  end

  class Classification < Base
    attr_accessor :description
  end

  class Department < Base
    attr_accessor :name
  end

  class Bio < Base
    attr_accessor :text, :employee_id, :employee
  end

  class TeamMembership < Base
    attr_accessor :employee_id, :team_id
  end

  class Team < Base
    attr_accessor :name, :team_memberships
  end

  class CreditCard < Base
    attr_accessor :number, :description
  end

  class Visa < CreditCard
    attr_accessor :visa_rewards

    def initialize(*)
      super
      @visa_rewards ||= []
    end
  end

  class Mastercard < CreditCard
  end

  class VisaReward < Base
    attr_accessor :visa_id, :points
  end

  class Book < Base
    attr_accessor :title, :author_id
  end

  class State < Base
    attr_accessor :name
  end

  class Adapter < Graphiti::Adapters::Null
    def order(scope, att, dir)
      scope[:sort] ||= []
      scope[:sort] << { att => dir }
      scope
    end

    def base_scope(model)
      {}
    end

    def paginate(scope, current_page, per_page)
      scope.merge!(page: current_page, per: per_page)
    end

    def filter(scope, name, value)
      scope[:conditions] ||= {}
      scope[:conditions].merge!(name => value)
      scope
    end
    alias :filter_integer_eq :filter
    alias :filter_string_eq :filter
    alias :filter_big_decimal_eq :filter
    alias :filter_float_eq :filter
    alias :filter_date_eq :filter
    alias :filter_datetime_eq :filter
    alias :filter_boolean_eq :filter
    alias :filter_hash_eq :filter
    alias :filter_array_eq :filter

    # No need for actual logic to fire
    def count(scope, attr)
       "poro_count_#{attr}"
    end

    def sum(scope, attr)
      "poro_sum_#{attr}"
    end

    def average(scope, attr)
      "poro_average_#{attr}"
    end

    def maximum(scope, attr)
      "poro_maximum_#{attr}"
    end

    def minimum(scope, attr)
      "poro_minimum_#{attr}"
    end

    def create(model, attributes)
      model.create(attributes)
    end

    def resolve(scope)
      ::PORO::DB.all(scope)
    end
  end

  class EmployeeSerializer < Graphiti::Serializer
    extra_attribute :stack_ranking do
      rand(999)
    end

    is_admin = proc { |c| @context && @context.current_user == 'admin' }
    extra_attribute :admin_stack_ranking, if: is_admin do
      rand(999)
    end

    extra_attribute :runtime_id do
      @context.runtime_id
    end
  end

  class ApplicationResource < Graphiti::Resource
    self.adapter = Adapter
    self.abstract_class = true

    def base_scope
      { type: self.model.name.demodulize.underscore.pluralize.to_sym }
    end
  end

  class EmployeeResource < ApplicationResource
    self.serializer = PORO::EmployeeSerializer
    attribute :first_name, :string
    attribute :last_name, :string
    attribute :age, :integer
    extra_attribute :worth, :integer do
      100
    end
    attribute :salary, :integer, readable: :admin? do
      100_000
    end
    has_many :positions
    many_to_many :teams, foreign_key: { employee_teams: :employee_id }

    def admin?
      context && context.current_user == 'admin'
    end
  end

  class PositionResource < ApplicationResource
    attribute :employee_id, :integer, only: [:filterable]
    attribute :title, :string
    attribute :rank, :integer
    extra_attribute :score, :integer do
      200
    end
    belongs_to :department
  end

  class ClassificationResource < ApplicationResource
  end

  class DepartmentResource < ApplicationResource
    attribute :name, :string
  end

  class BioResource < ApplicationResource
  end

  class TeamResource < ApplicationResource
    belongs_to_many :employees, as: :teams
  end

  class CreditCardResource < ApplicationResource
    self.polymorphic = %w(PORO::VisaResource PORO::MastercardResource)

    def base_scope
      { type: [:visas, :mastercards] }
    end

    attribute :number, :integer
    attribute :description, :string
  end

  class VisaResource < CreditCardResource
    attribute :description, :string do
      'visa description'
    end
    attribute :visa_only_attr, :string do
      'visa only'
    end

    def base_scope
      { type: :visas }
    end

    has_many :visa_rewards
  end

  class MastercardResource < CreditCardResource
    attribute :description, :string do
      'mastercard description'
    end

    def base_scope
      { type: :mastercards }
    end
  end

  class VisaRewardResource < ApplicationResource
    attribute :visa_id, :integer, only: [:filterable]
    attribute :points, :integer

    def base_scope
      { type: :visa_rewards }
    end
  end

  class ApplicationSerializer < Graphiti::Serializer
  end
end
