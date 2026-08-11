# ChatApp — ZXADASA ready source

This package contains the current ChatApp source available in the conversation, arranged so the repository root contains `project.yml` and `Sources/ChatApp`.

Before running GitHub Actions, upload/commit the whole folder to the `zxadasa/zxadasa` repository root.

The workflow now verifies `Sources/ChatApp` before running XcodeGen, so a missing-source checkout is reported immediately.
