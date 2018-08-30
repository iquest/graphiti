require 'spec_helper'

RSpec.describe 'serialization' do
  include_context 'resource testing'

  let(:resource) do
    Class.new(PORO::ApplicationResource) do
      self.type = :employees
      def self.name
        'PORO::EmployeeResource'
      end
    end
  end

  let(:attributes) { json['data'][0]['attributes'] }

  context 'when serializer is automatically generated' do
    it 'generates a serializer class' do
      expect(resource.serializer.ancestors)
        .to include(Graphiti::Serializer)
    end

    it 'has same type as resource' do
      expect(resource.serializer.type_val).to eq(:employees)
    end

    it 'has all readable attributes of resource' do
      resource.attribute :foo, :string
      expect(resource.serializer.attribute_blocks.keys).to include(:foo)
    end

    it 'has all readable sideloads of the resource' do
      resource.allow_sideload :foobles, type: :has_many
      resource.allow_sideload :barble, type: :belongs_to
      expect(resource.serializer.relationship_blocks.keys)
        .to eq([:foobles, :barble])
    end

    it 'renders correctly' do
      PORO::Employee.create(first_name: 'John')
      resource.attribute :first_name, :string
      render
      expect(json['data'][0]['type']).to eq('employees')
      expect(json['data'][0]['attributes']).to eq('first_name' => 'John')
    end

    describe 'helper functions' do
      let(:app_serializer) do
        Class.new(Graphiti::Serializer) do
          def my_method
            'bar!'
          end
        end
      end

      before do
        allow(PORO::ApplicationResource).to receive(:name) { class_name }
        PORO::Employee.create
      end

      def define_resource
        resource.class_eval do
          attribute :foo, :string do
            my_method
          end

          private

          def my_method
            'foo!'
          end
        end
      end

      let(:class_name) { 'PORO::EmployeeResource' }

      it 'can call methods on the resource' do
        define_resource
        render
        expect(d[0].foo).to eq('foo!')
      end

      context 'when application serializer defined' do
        context 'in a namespace' do
          before do
            stub_const('PORO::ApplicationSerializer', app_serializer)
            define_resource
          end

          it 'can call methods on the namespaced ApplicationSerializer' do
            render
            expect(d[0].foo).to eq('bar!')
          end
        end

        context 'not in a namespace' do
          let(:class_name) { 'EmployeeResource' }

          before do
            stub_const('ApplicationSerializer', app_serializer)
            define_resource
          end

          it 'can call methods on ApplicationSerializer' do
            render
            expect(d[0].foo).to eq('bar!')
          end
        end

        context 'but not a descendent of Graphiti::Serializer' do
          let(:app_serializer) { double.as_null_object }

          it 'cannot call methods on ApplicationSerializer' do
            define_resource
            render
            expect(d[0].foo).to eq('foo!')
          end
        end
      end
    end

    describe 'types' do
      # can coerce everything...
      context 'when string' do
        before do
          resource.attribute :age, :string
        end

        it 'coerces' do
          PORO::Employee.create(age: 1)
          render
          expect(attributes['age']).to eq('1')
        end
      end

      context 'when integer' do
        before do
          resource.attribute :age, :integer
        end

        it 'coerces strings' do
          PORO::Employee.create(age: '40')
          render
          expect(attributes['age']).to eq(40)
        end

        it 'allows nils' do
          PORO::Employee.create(age: nil)
          render
          expect(attributes['age']).to eq(nil)
        end

        context 'when cannot coerce' do
          before do
            PORO::Employee.create(age: 'foo')
          end

          it 'raises error' do
            expect {
              render
            }.to raise_error(Graphiti::Errors::TypecastFailed)
          end
        end
      end

      # NB: json is string because json can't support
      # the level of precision BigDecimal requires
      context 'when decimal' do
        before do
          resource.attribute :age, :big_decimal
        end

        it 'coerces integers' do
          PORO::Employee.create(age: 40)
          render
          expect(attributes['age']).to eq('0.4E2')
        end

        it 'coerces strings' do
          PORO::Employee.create(age: '40.01')
          render
          expect(attributes['age']).to eq('0.4001E2')
        end

        it 'allows nils' do
          PORO::Employee.create(age: nil)
          render
          expect(attributes['age']).to eq(nil)
        end

        context 'when cannot coerce' do
          before do
            PORO::Employee.create(age: {})
          end

          it 'raises error' do
            expect {
              render
            }.to raise_error(Graphiti::Errors::TypecastFailed)
          end
        end
      end

      context 'when float' do
        before do
          resource.attribute :age, :float
        end

        it 'coerces strings' do
          PORO::Employee.create(age: '40.01')
          render
          expect(attributes['age']).to eq(40.01)
        end

        it 'coerces integers' do
          PORO::Employee.create(age: 40)
          render
          expect(attributes['age']).to eq(40.0)
        end

        it 'allows nils' do
          PORO::Employee.create(age: nil)
          render
          expect(attributes['age']).to eq(nil)
        end

        context 'when cannot coerce' do
          before do
            PORO::Employee.create(age: {})
          end

          it 'raises error' do
            expect {
              render
            }.to raise_error(Graphiti::Errors::TypecastFailed)
          end
        end
      end

      context 'when boolean' do
        before do
          resource.attribute :age, :boolean
        end

        it 'coerces strings' do
          PORO::Employee.create(age: 'true')
          render
          expect(attributes['age']).to eq(true)
        end

        it 'coerces integers' do
          PORO::Employee.create(age: 1)
          render
          expect(attributes['age']).to eq(true)
        end

        it 'allows nils' do
          PORO::Employee.create(age: nil)
          render
          expect(attributes['age']).to eq(nil)
        end

        context 'when false' do
          it 'renders false, not nil' do
            PORO::Employee.create(age: false)
            render
            expect(attributes['age']).to eq(false)
          end
        end

        context 'when cannot coerce' do
          before do
            PORO::Employee.create(age: 1.1)
          end

          it 'raises error' do
            expect {
              render
            }.to raise_error(Graphiti::Errors::TypecastFailed)
          end
        end
      end

      context 'when date' do
        before do
          resource.attribute :age, :date
        end

        it 'coerces Date to correct string format' do
          PORO::Employee.create(age: Date.parse('2018/01/06'))
          render
          expect(attributes['age']).to eq('2018-01-06')
        end

        it 'coerces Time to correct date string format' do
          time = Time.parse('2018/01/06 4:13pm')
          PORO::Employee.create(age: time)
          render
          expect(attributes['age']).to eq('2018-01-06')
        end

        it 'coerces strings to date format' do
          PORO::Employee.create(age: '2018/01/06')
          render
          expect(attributes['age']).to eq('2018-01-06')
        end

        it 'allows nils' do
          PORO::Employee.create(age: nil)
          render
          expect(attributes['age']).to eq(nil)
        end

        context 'when only month' do
          before do
            PORO::Employee.create(age: '2018/01')
          end

          # You don't want this type if you don't want this conversion
          # Use a different type, or register a new custom type
          it 'defaults to first of the month' do
            render
            expect(attributes['age']).to eq('2018-01-01')
          end
        end

        context 'when cannot coerce' do
          before do
            PORO::Employee.create(age: '1')
          end

          it 'raises error' do
            expect {
              render
            }.to raise_error(Graphiti::Errors::TypecastFailed)
          end
        end
      end

      # iso8601
      # If zone is present, it is preserved
      # If not present, falls back to UTC
      context 'when datetime' do
        before do
          resource.attribute :age, :datetime
        end

        # NB Time has an implicit zone based on system time
        # Here we are setting the zone explicitly
        it 'coerces Time correctly' do
          time = Time.parse('2018-01-06 4:36pm PST')
          PORO::Employee.create(age: time)
          render
          expect(attributes['age']).to eq('2018-01-06T16:36:00-08:00')
        end

        # Default zone UTC
        # NB: Internal custom type required for this
        it 'coerces Date correctly' do
          date = Date.parse('2018-01-06')
          PORO::Employee.create(age: date)
          render
          expect(attributes['age']).to eq('2018-01-06T00:00:00+00:00')
        end

        it 'preserves time zones on Date' do
          date_time = DateTime.parse('2018-01-06 4:36pm PST')
          PORO::Employee.create(age: date_time)
          render
          expect(attributes['age']).to eq('2018-01-06T16:36:00-08:00')
        end

        # No zone, defaults to UTC
        # NB: Internal custom type required for this
        it 'coerces DateTime correctly' do
          date_time = DateTime.parse('2018-01-06 4:36pm')
          PORO::Employee.create(age: date_time)
          render
          expect(attributes['age']).to eq('2018-01-06T16:36:00+00:00')
        end

        # NB: Internal custom type required for this
        it 'preserves DateTime zones' do
          date_time = DateTime.parse('2018-01-06 4:36pm PST')
          PORO::Employee.create(age: date_time)
          render
          expect(attributes['age']).to eq('2018-01-06T16:36:00-08:00')
        end

        # Missing zone defaults to UTC
        it 'coerces strings correctly' do
          PORO::Employee.create(age: '2018-01-06 4:36pm')
          render
          expect(attributes['age']).to eq('2018-01-06T16:36:00+00:00')
        end

        # Preserves time zone
        it 'preserves string time zones' do
          PORO::Employee.create(age: '2018-01-06 4:36pm PST')
          render
          expect(attributes['age']).to eq('2018-01-06T16:36:00-08:00')
        end

        it 'allows nils' do
          PORO::Employee.create(age: nil)
          render
          expect(attributes['age']).to eq(nil)
        end

        context 'when cannot coerce' do
          before do
            PORO::Employee.create(age: '1')
          end

          # NB requires custom type
          it 'raises error' do
            expect {
              render
            }.to raise_error(Graphiti::Errors::TypecastFailed)
          end
        end
      end

      context 'when hash' do
        before do
          resource.attribute :age, :hash
        end

        it 'works' do
          PORO::Employee.create(age: { foo: 'bar' })
          render
          expect(attributes['age']).to eq({ 'foo' => 'bar' })
        end

        context 'when cannot coerce' do
          before do
            PORO::Employee.create(age: [:foo, :bar])
          end

          it 'raises error' do
            expect {
              render
            }.to raise_error(Graphiti::Errors::TypecastFailed)
          end
        end
      end

      context 'when array' do
        before do
          resource.attribute :age, :array
        end

        it 'works' do
          PORO::Employee.create(age: [1, 2, 3])
          render
          expect(attributes['age']).to eq([1, 2, 3])
        end

        it 'applies basic to_json conversion of elements' do
          time = Time.parse('01-06-2018 4:36pm PST')
          PORO::Employee.create(age: [time])
          render
          expect(attributes['age']).to eq(["2018-06-01 16:36:00 -0800"])
        end

        # If we did Array(value), you'd get something incorrect
        # for hashes
        it 'raises error on single values' do
          PORO::Employee.create(age: 1)
          expect {
            render
          }.to raise_error(Graphiti::Errors::TypecastFailed)
        end

        context 'when cannot coerce' do
          before do
            PORO::Employee.create(age: { foo: 'bar' })
          end

          it 'raises error' do
            expect {
              render
            }.to raise_error(Graphiti::Errors::TypecastFailed)
          end
        end
      end

      # test for all array_of_*
      context 'when array_of_integers' do
        before do
          resource.attribute :age, :array_of_integers
        end

        it 'works' do
          PORO::Employee.create(age: [1, 2, 3])
          render
          expect(attributes['age']).to eq([1, 2, 3])
        end

        it 'applies basic coercion of elements' do
          PORO::Employee.create(age: ['1', '2', '3'])
          render
          expect(attributes['age']).to eq([1, 2, 3])
        end

        # If we did Array(value), you'd get something incorrect
        # for hashes
        it 'raises error on single values' do
          PORO::Employee.create(age: 1)
          expect {
            render
          }.to raise_error(Graphiti::Errors::TypecastFailed)
        end

        context 'when cannot coerce' do
          before do
            PORO::Employee.create(age: { foo: 'bar' })
          end

          it 'raises error' do
            expect {
              render
            }.to raise_error(Graphiti::Errors::TypecastFailed)
          end
        end
      end

      context 'when custom type' do
        before do
          type = Dry::Types::Definition
            .new(nil)
            .constructor { |input|
              'custom!'
            }
          Graphiti::Types[:custom] = {
            read: type,
            write: type,
            params: type,
            kind: 'scalar',
            description: 'test'
          }
          resource.attribute :age, :custom
        end

        after do
          Graphiti::Types.map.delete(:custom)
        end

        it 'works' do
          PORO::Employee.create(age: 'asdf')
          render
          expect(attributes['age']).to eq('custom!')
        end
      end

      context 'when attribute has custom proc' do
        before do
          resource.attribute :age, :integer do
            '100'
          end
        end

        it 'still goes through coercion' do
          PORO::Employee.create(age: '40')
          render
          expect(attributes['age']).to eq(100)
        end
      end

      context 'when an attribute has custom proc *via the serializer*' do
        before do
          resource.serializer.class_eval do
            attribute :age do
              '200'
            end
          end
          resource.attribute :age, :integer
        end

        it 'still goes through coercion' do
          PORO::Employee.create(age: '40')
          render
          expect(attributes['age']).to eq(200)
        end
      end

      context 'when an extra attribute' do
        before do
          params[:extra_fields] = { employees: 'salary' }
        end

        it 'still goes through type coercion' do
          resource.extra_attribute :salary, :integer
          PORO::Employee.create(salary: '40')
          render
          expect(attributes['salary']).to eq(40)
        end

        context 'with a custom block' do
          before do
            resource.extra_attribute :salary, :integer do
              '100'
            end
          end

          it 'still goes through type coercion' do
            PORO::Employee.create(salary: '40')
            render
            expect(attributes['salary']).to eq(100)
          end
        end

        context 'with a custom block *via the serializer*' do
          before do
            resource.serializer.class_eval do
              attribute :salary do
                '200'
              end
            end
            resource.extra_attribute :salary, :integer
          end

          it 'still goes through coercion' do
            PORO::Employee.create(salary: '40')
            render
            expect(attributes['salary']).to eq(200)
          end
        end
      end
    end

    context 'when the resource attribute has a block' do
      before do
        resource.attribute :foo, :string do
          'without object'
        end
        resource.attribute :bar, :string do
          @object.first_name.upcase
        end
      end

      it 'is used in serialization' do
        PORO::Employee.create(first_name: 'John')
        render
        data = json['data'][0]
        attributes = data['attributes']
        expect(attributes).to eq({
          'foo' => 'without object',
          'bar' => 'JOHN'
        })
      end
    end

    context 'when the resource has a different serializer than the model' do
      let(:serializer) do
        Class.new(Graphiti::Serializer) do
          attribute :first_name do
            'override'
          end
        end
      end

      before do
        PORO::Employee.create(first_name: 'John')
        resource.serializer = serializer
      end

      it 'uses the resource serializer no matter what' do
        render
        expect(json['data'][0]['type']).to eq('employees')
        expect(json['data'][0]['attributes']).to eq('first_name' => 'override')
      end
    end

    context 'when a sideload is not readable' do
      before do
        resource.allow_sideload :hidden, readable: false
      end

      it 'is not applied to the serializer' do
        expect(resource.serializer.relationship_blocks.keys)
          .to_not include(:hidden)
      end
    end

    context 'when a sideload macro not readable' do
      before do
        resource.belongs_to :hidden, readable: false
      end

      it 'is not applied to the serializer' do
        expect(resource.serializer.relationship_blocks.keys)
          .to_not include(:hidden)
      end
    end

    context 'when an attribute is not readable' do
      before do
        resource.attribute :foo, :string, readable: false
      end

      it 'is not applied to the serializer' do
        expect(resource.serializer.attribute_blocks.keys).to eq([])
      end
    end

    context 'when an attribute is conditionally readable' do
      before do
        PORO::Employee.create(first_name: 'John')
        resource.class_eval do
          attribute :first_name, :string
          attribute :foo, :string, readable: :admin? do
            'bar'
          end

          def admin?
            !!context.admin
          end
        end
      end

      context 'and the guard passes' do
        around do |e|
          Graphiti.with_context(OpenStruct.new(admin: true)) do
            e.run
          end
        end

        it 'is serialized' do
          render
          expect(json['data'][0]['attributes']['foo']).to eq('bar')
        end
      end

      context 'and the guard fails' do
        around do |e|
          Graphiti.with_context(OpenStruct.new(admin: false)) do
            e.run
          end
        end

        it 'is not serialized' do
          render
          expect(json['data'][0]['attributes']).to_not have_key('foo')
        end
      end
    end
  end

  context 'when serializer is explicitly assigned' do
    it 'generates a serializer class' do
      expect(resource.serializer.ancestors)
        .to include(Graphiti::Serializer)
    end

    it 'has same type as resource' do
      expect(resource.serializer.type_val).to eq(:employees)
    end

    it 'has all readable attributes of resource' do
      resource.attribute :foo, :string
      expect(resource.serializer.attribute_blocks.keys).to eq([:foo])
    end

    context 'when an attribute is not readable' do
      before do
        resource.attribute :foo, :string, readable: false
      end

      it 'is not applied to the serializer' do
        expect(resource.serializer.attribute_blocks.keys).to eq([])
      end
    end
  end

  describe 'extra attributes' do
    before do
      PORO::Employee.create(first_name: 'John')
      resource.attribute :foo, :string do
        'bar'
      end
      resource.extra_attribute :first_name, :string
    end

    it 'adds extra attributes to the serializer' do
      params[:extra_fields] = { employees: 'first_name' }
      expect(resource.serializer.attribute_blocks.keys)
        .to match_array([:first_name, :foo])
      render
      expect(json['data'][0]['attributes']).to eq({
        'foo' => 'bar',
        'first_name' => 'John'
      })
    end

    it 'does not render extra attributes if not requested' do
      render
      expect(json['data'][0]['attributes']).to_not have_key('first_name')
    end

    context 'when passing a block' do
      before do
        resource.serializer.attribute_blocks.delete(:first_name)
        resource.extra_attribute :first_name, :string do
          'im extra, serialized'
        end
      end

      it 'is used during serialization' do
        params[:extra_fields] = { employees: 'first_name' }
        render
        expect(json['data'][0]['attributes']['first_name'])
          .to eq('im extra, serialized')
      end
    end
  end

  describe 'links' do
    let!(:employee) { PORO::Employee.create }

    def positions
      json['data'][0]['relationships']['positions']
    end

    around do |e|
      Graphiti.config.context_for_endpoint = ->(path, action) {
        double('test context')
      }
      e.run
      Graphiti.config.context_for_endpoint = nil
    end

    context 'when not autolinked by default' do
      before do
        resource.autolink = false
      end

      it 'does not generate links by default' do
        resource.has_many :positions
        render
        expect(positions).to_not have_key('links')
      end

      it 'does generate links when link: true passed' do
        resource.has_many :positions, link: true
        render
        expect(positions).to have_key('links')
      end

      context 'when manually linking' do
        before do
          resource.has_many :positions do
            link do |employee|
              "/special/positions?blah=#{employee.id}"
            end
          end
        end

        it 'generates link' do
          render
          expect(positions['links']['related'])
            .to eq('/special/positions?blah=1')
        end

        context 'when links_on_demand' do
          around do |e|
            original = Graphiti.config.links_on_demand
            begin
              Graphiti.config.links_on_demand = true
              e.run
            ensure
              Graphiti.config.links_on_demand = original
            end
          end

          it 'adds links=true to url' do
            params[:links] = true
            render
            expect(positions['links']['related'])
              .to eq('/special/positions?blah=1&links=true')
          end
        end
      end
    end

    context 'when only linking if requested' do
      around do |e|
        resource.autolink = true
        params[:include] = 'positions'
        resource.has_many :positions
        original = Graphiti.config.links_on_demand
        begin
          Graphiti.config.links_on_demand = true
          e.run
        ensure
          Graphiti.config.links_on_demand = original
        end
      end

      context 'and not requested in url' do
        it 'does not render links' do
          render
          expect(positions).to_not have_key('links')
        end
      end

      context 'and requested in url' do
        before do
          params[:links] = true
        end

        it 'does render links' do
          render
          expect(positions).to have_key('links')
        end

        it 'appends ?links=true to link' do
          render
          expect(positions['links']['related'])
            .to eq('/poro/positions?filter[employee_id]=1&links=true')
        end
      end
    end

    context 'when autolinked by default' do
      before do
        resource.autolink = true
      end

      context 'and a has_many relationship' do
        it 'links correctly' do
          resource.has_many :positions
          render
          expect(positions['links']['related'])
            .to eq('/poro/positions?filter[employee_id]=1')
        end

        context 'opting-out of linking' do
          before do
            resource.has_many :positions, link: false
          end

          it 'does not link' do
            render
            expect(positions).to_not have_key('links')
          end
        end

        context 'with custom params' do
          before do
            resource.has_many :positions do
              params do |hash|
                hash[:sort] = '-id'
              end
            end
          end

          it 'links correctly' do
            render
            expect(positions['links']['related'])
              .to eq('/poro/positions?filter[employee_id]=1&sort=-id')
          end
        end

        context 'with runtime params' do
          xit 'links correctly' do

          end
        end

        context 'that does not have an index endpoint' do
          before do
            Graphiti.config.context_for_endpoint = ->(path, action) {
              action == :index ? nil : double
            }
          end

          it 'raises error' do
            expect {
              resource.has_many :positions
            }.to raise_error(Graphiti::Errors::InvalidLink, /Make sure the endpoint \"\/poro\/positions\" exists with action :index/)
          end
        end

        context 'that does not have a context_for_endpoint config' do
          before do
            Graphiti.config.context_for_endpoint = nil
          end

          it 'raises error' do
            expect {
              resource.has_many :positions
            }.to raise_error(Graphiti::Errors::Unlinkable, /Graphiti.config.context_for_endpoint/)
          end
        end
      end

      context 'and a polymorphic_belongs_to relationship' do
        let(:mastercard_resource) do
          Class.new(PORO::MastercardResource) do
            def self.name;'PORO::MastercardResource';end
            primary_endpoint '/poro/mastercards'
          end
        end

        before do
          employee.update_attributes \
            credit_card_type: 'Mastercard',
            credit_card_id: 789
        end

        def define_relationship
          _mastercard_resource = mastercard_resource
          resource.polymorphic_belongs_to :credit_card do
            group_by(:credit_card_type) do
              on(:Visa).belongs_to :visa
              on(:Mastercard).belongs_to :mastercard,
                resource: _mastercard_resource
            end
          end
        end

        it 'works' do
          define_relationship
          render
          credit_card = json['data'][0]['relationships']['credit_card']
          expect(credit_card['links']['related'])
            .to eq('/poro/mastercards/789')
        end

        context 'but one child does not have an endpoint' do
          before do
            mastercard_resource.endpoint = nil
          end

          it 'does not link' do
            define_relationship
            render
            credit_card = json['data'][0]['relationships']['credit_card']
            expect(credit_card).to_not have_key('links')
          end
        end
      end

      context 'and a many_to_many relationship' do
        let(:team_resource) do
          Class.new(PORO::TeamResource) do
            def self.name;'PORO::TeamResource';end
          end
        end

        def define_relationship
          resource.many_to_many :teams,
            resource: team_resource,
            foreign_key: { employee_teams: :employee_id }
        end

        it 'works' do
          define_relationship
          render
          expect(json['data'][0]['relationships']['teams']['links']['related'])
            .to eq('/poro/teams?filter[employee_id]=1')
        end
      end

      context 'and a has_one relationship' do
        before do
          resource.has_one :bio
        end

        it 'links to index endpoint' do
          render
          expect(json['data'][0]['relationships']['bio']['links']['related'])
            .to eq("/poro/bios?filter[employee_id]=#{employee.id}")
        end
      end

      context 'and a belongs_to relationship' do
        let!(:employee) { PORO::Employee.create(classification_id: 789) }

        def classification
          json['data'][0]['relationships']['classification']
        end

        it 'links correctly' do
          resource.belongs_to :classification
          render
          expect(classification['links']['related'])
            .to eq('/poro/classifications/789')
        end

        context 'that has custom params' do
          before do
            resource.belongs_to :classification do
              params do |hash|
                hash[:fields] = { classifications: 'title' }
              end
            end
          end

          it 'merges the params into the link' do
            render
            expect(classification['links']['related'])
              .to eq('/poro/classifications/789?fields[classifications]=title')
          end
        end

        # ie fields
        xit 'runtime options' do
        end

        context 'that does not have a show endpoint' do
          before do
            Graphiti.config.context_for_endpoint = ->(path, action) {
              action == :show ? nil : double
            }
          end

          it 'raises error' do
            expect {
              resource.belongs_to :classification
            }.to raise_error(Graphiti::Errors::InvalidLink, /Make sure the endpoint \"\/poro\/classifications\" exists with action :show/)
          end
        end

        context 'with runtime params' do
          xit 'links correctly' do

          end
        end
      end
    end
  end
end