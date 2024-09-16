# Get the difference between two attribute sets
let first = {
  first = 1,
  second = 2,
  fourth = { a = 1, b = 1 }
}
in
let second = {
  first = 1,
  second = 2,
  thrid = 3,
  fourth = { a = 1, b = 1 }
}
in

# The first call gets you what was removed and those should have a nice way to be removed from the api
let rec diff = fun old new =>
  std.record.to_array new
  |> std.array.fold_right
    (
      fun e acc =>
        std.trace
          "%{e.field}"
          (
            if std.typeof e.value == 'Record then
              let nested = (diff first."%{e.field}" e.value) in
              if nested != {} then
                std.record.update e.field nested acc
              else
                acc
            else if std.record.has_field e.field old then
              acc
            else
              std.record.update
                e.field
                e.value
                acc
          )
    )
    {}
in
diff first second
