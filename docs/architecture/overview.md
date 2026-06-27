# Architecture Overview

RailsDoctor is a small command framework:

```text
Rails::Command::DoctorCommand
  -> RailsDoctor::Runner
    -> RailsDoctor::Context
    -> RailsDoctor::Registry
      -> RailsDoctor::Check
        -> RailsDoctor::Result
    -> RailsDoctor::Reporter
```

Checks are loaded from `lib/rails_doctor/checks/` and third-party gems can add
their own by calling `RailsDoctor.register`.
