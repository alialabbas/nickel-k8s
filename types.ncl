{
  Networking
    | doc m%"Collection of networking related types, ports, ipv4, etc"%
    = {
      Port
        | doc "Valid port number between 0 to 65535"
        = Numbers.InRange 0 65535,

      IPAddr
        | doc "IPv4 address"
        =
          std.contract.from_predicate
            (
              fun ip =>
                let parts = std.string.split "." ip in
                if std.array.length parts == 4 then
                  parts |> std.array.all (fun val => let n = std.string.to_number val in n >= 0 && n <= 255)
                else
                  false
            ),
    },

  Numbers = {
    InRange
      | doc "Enforce a number in range, both bounds inclusive"
      = fun min max => std.contract.from_predicate (fun val => std.is_number val && val >= min && val <= max),

    NumberOrPercentage
      | doc "Custom type that can be represented as number, e.g. 10 or percentage 23%"
      = fun label value =>
        std.typeof value
        |> match {
          'Number => value,
          'String => if std.string.is_match "^[0-9]+%$" value then value else std.contract.blame_with_message "Expected a string number precented as percentage e.g. 10%" label,
          _ => std.contract.blame_with_message "Expected either a number or a string percentage" label
        }
  },

  Arrays = {
    Single
      | doc "Contract ensuring the array has a single item"
      = fun label value => if std.array.length value == 1 then value else std.contract.blame_with_message ("Array has multiple fields, expected single") label,

    MinItems
      | doc m%"Fail if the array doesn't have the min count, inclusive"%
      = fun minItemsCount => std.contract.from_predicate (fun val => std.array.length val >= minItemsCount),

    Exactly
      | doc m%"Contract ensuring the array is of a specific length"%
      = fun count => std.contract.from_predicate (fun val => std.array.length val == count),

    Nullable | doc m%"Apply the Contract to an array and allow it to also be assigned as null"%
      = fun contract =>
        fun label value =>
          if value == null then
            null
          else
            std.contract.apply (Array contract) label value,

    # Works probably should be a Set type or just part of Records types
    UniqueRecords
      | doc m%"Simple set implementation for an array of records"%
      = fun field label array =>
          if array
          |> std.array.fold_right
            (
              fun val acc =>
                if std.record.has_field (std.record.get field val) acc then
                  std.record.update (std.record.get field val) (std.record.get (std.record.get field val) acc + 1) acc
                else
                  std.record.insert (std.record.get field val) 1 acc
            )
            {}
          |> std.record.to_array
          |> std.array.all (fun x => x.value == 1) == false then
            std.contract.blame_with_message "duplicated record fields detected" label
          else
            array,
  },

  Strings = {
    NotEmpty
      | doc m%"Enforce a string is never an empty one"%
      = std.contract.from_predicate (fun val => std.is_string val && val != "")
  },

  Records | doc "Extension of various contracts applied to a record"
    = {
      MutualExclusive
        | doc "enforce mutual exclusion on a set of record fields"
        = fun fields =>
          (
            fun label record =>
              let declared_fields = std.array.map (fun kvp => kvp.field) std.record.to_array record in
              let found =
                std.array.fold_right
                  (fun field acc => if (std.record.has_field field record) then acc + 1 else acc)
                  0
                  fields
              in
              if found != 1 then
                let errMsg =
                  fields
                  |> std.array.fold_right (fun field acc => acc ++ " " ++ field) "The following fields are mutually exclusive:"
                in
                std.contract.blame_with_message errMsg label
              else
                record
          ),

      Nullable
        | doc "A record contract that can be null"
        = fun contract label record =>
            if record == null then
              record
            else
              std.contract.apply contract label record,

      NameOfRecord
        | doc "Assert the record a single root record and return its name, this will fail if the record has multiple roots, e.g. test = { first, test}"
        = fun record =>
          let result =
            record
            |> std.record.to_array
            |> std.array.map (fun e => e.field)
          in
          (result | Arrays.Single) |> std.array.first,

      FieldsAreOfType
        | doc "Apply a contract to a dictinoary {_: } key fields"
        = fun contract label value =>
          value
          |> std.record.to_array
          |> std.array.map
            (
              fun e =>
                {
                  field =
                    (
                      std.contract.apply contract label e.field
                    )
                    |> std.to_string,
                  value = e.value
                }
            )
          |> std.record.from_array,
    },
}
