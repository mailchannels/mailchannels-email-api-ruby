# Release checklist

This client is not yet published to RubyGems. The version in source is a candidate,
not proof of an available gem. Support is dev@mailchannels.com; a named release
operator and MailChannels-controlled RubyGems publisher must be established.

1. Create the company-controlled RubyGems account, complete email verification/MFA,
   and keep recovery credentials in company credential management. Recheck gem name
   availability before release. No token belongs in source, CI output or issues.
2. Review the HTTP transport against a local TLS fixture (verification, redirect,
   timeout, disconnect and no-retry behavior). Six native TLS tests now cover all but the read timeout on Ruby 3.2/3.4 alongside the unit
   tests. Re-run the full suite when transport/runtime/dependencies change. Native
   loopback tests do not establish real provider acceptance or delivery.
3. Run the test matrix and build/install checks. Obtain separately authorized live
   dry-run validation using a configured sender and permitted recipient. A dry run
   must return 200 with validated? true and accepted? false. No live send is part of CI.
4. Review gem files, license, dependencies, README, source/issue URLs and support.
   Build the exact reviewed commit with gem build mailchannels-email-api.gemspec.
5. Publish the reviewed artifact using the company account and normal authenticated
   gem push flow. This repository has no automated publishing workflow or secrets.
6. Verify clean installation from RubyGems, public metadata/docs and version/checksum.
   Only then tag/release the matching source and propose Ruby Toolbox catalog inclusion.

Do not describe this as an Action Mailer adapter. It is a direct send/validate client.
HTTP 202 is acceptance for processing, not delivery; uncertain sends must not retry blindly.
