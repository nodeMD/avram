class LuckyRecord::BaseFormTemplate
  macro setup(model_type, fields, table_name)
    class BaseForm
      property? performed : Bool = false
      getter :record

      @record : {{ model_type }}?
      @params : Hash(String, String)
      @valid : Bool = true

      @@table_name = {{ table_name }}
      @@allowed_param_keys = [] of String
      @@schema_class = {{ model_type }}

      private def extract_changes_from_params
        allowed_params.each do |key, value|
          {% for field in fields %}
            set_{{field[:name]}}_from_param value if key == {{field[:name].stringify}}
          {% end %}
        end
      end

      def initialize(@params)
        extract_changes_from_params
      end

      def initialize(**params)
        params_with_stringified_keys = {} of String => String
        params.each do |key, value|
          params_with_stringified_keys[key.to_s] = value
        end

        @params = params_with_stringified_keys
        extract_changes_from_params
      end

      def initialize(@record, @params)
        extract_changes_from_params
      end

      def initialize(@record, @params)
        params_with_stringified_keys = {} of String => String
        params.each do |key, value|
          params_with_stringified_keys[key.to_s] = value
        end

        @params = params_with_stringified_keys
        extract_changes_from_params
      end

      def valid? : Bool
        call
        # TODO: run_auto_generated_validations
        fields.all? &.valid?
      end

      def call
        # TODO add default validate_required for non-nilable fields
      end

      def self.save(params)
        form = new(params)
        if form.save
          yield form, form.record
        else
          yield form, nil
        end
      end

      def self.update(record, with params)
        form = new(record, params)
        if form.save
          yield form, form.record.not_nil!
        else
          yield form, form.record.not_nil!
        end
      end

      def save_succeeded?
        !save_failed?
      end

      def save_failed?
        !valid? && performed?
      end

      macro allow(*field_names)
        \{% for field_name in field_names %}
          def \{{field_name.id}}
            _\{{field_name.id}}
          end

          @@allowed_param_keys << "\{{field_name.id}}"
        \{% end %}
      end

      def changes
        _changes = {} of Symbol => String?
        fields.each do |field|
          if field.changed?
            _changes[field.name] = field.value.to_s
          end
        end
        _changes
      end

      def save : Bool
        @performed = true

        record_id = @record.try &.id
        if record_id
          update record_id
        else
          insert
        end
      end

      private def insert
        self._created_at.value = Time.now
        self._updated_at.value = Time.now
        if valid?
          @record = LuckyRecord::Repo.run do |db|
            db.query insert_sql.statement, insert_sql.args do |rs|
              @@schema_class.from_rs(rs)
            end.first
          end

          true
        else
          false
        end
      end

      private def update(id)
        if valid?
          @record = LuckyRecord::Repo.run do |db|
            db.query update_query(id).statement_for_update(changes), update_query(id).args_for_update(changes) do |rs|
              @@schema_class.from_rs(rs)
            end.first
          end
          true
        else
          false
        end
      end

      private def update_query(id)
        LuckyRecord::QueryBuilder.new(@@table_name).
          where(LuckyRecord::Where::Equal.new(:id, id.to_s))
      end

      private def insert_sql
        LuckyRecord::Insert.new(@@table_name, changes)
      end

      def self.new_insert(**params)
        params_with_stringified_keys = {} of String => String
        params.each do |key, value|
          params_with_stringified_keys[key.to_s] = value
        end

        new(params_with_stringified_keys)
      end

      def self.new_update(to record, **params)
        params_with_stringified_keys = {} of String => String
        params.each do |key, value|
          params_with_stringified_keys[key.to_s] = value
        end

        new(record, params_with_stringified_keys)
      end

      {% for field in fields %}
        @_{{field[:name]}} : LuckyRecord::Field({{field[:type]}}::BaseType?)?

        def _{{field[:name]}}
          @_{{field[:name]}} ||= LuckyRecord::Field({{field[:type]}}::BaseType?).new(:{{field[:name].id}}, allowed_params["{{field[:name]}}"]?, @record.try(&.{{field[:name]}}))
        end

        def allowed_params
          @params.select(@@allowed_param_keys)
        end

        def set_{{field[:name]}}_from_param(value)
          cast_result = {{ field[:type] }}.cast(value)
          if cast_result.is_a? LuckyRecord::Type::SuccessfulCast
            _{{field[:name]}}.value = cast_result.value
          else
            _{{field[:name]}}.add_error "is invalid"
          end
        end
      {% end %}

      def fields
        [
          {% for field in fields %}
            _{{field[:name]}},
          {% end %}
        ]
      end
    end
  end
end