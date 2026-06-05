# ATLAS SETUP AUTOMATION

What is Atlas?

Atlas is a full-stack Rails/Ember application that powers HCP Terraform (formerly Terraform Cloud) at https://app.terraform.io. It provides both the backend API (Ruby on Rails + PostgreSQL) and frontend UI (Ember.js) for managing Terraform infrastructure workflows, supporting both cloud (SaaS) and self-hosted (Enterprise) deployments.

## PREREQUISITES
-   Download Docker Desktop and move it to Applications folder.
-   Request access to Hashicorp Okta and Hashicorp Okta Certificate using IBM AccessHub.
- Once the access is granted log into Artifactory through your Okta dashboard. 
- Request pull access to artifactory-users group which will also add the Artifactory tile to Okta. https://doormat.hashicorp.services/applications/access/artifactory/role/doormat-artifactory-users/option
![Requesting access to artifactory-users](images/doormat1.png)
- User should have a github account with access to the hashicorp organization. (Consult your Engineering Manager for more information getting access)

## SETUP
1.  Clone the repository
2.  ```bash
    chmod +x setup.sh
    ```
3.  ```bash
    ./setup.sh
    ```
4.  If script fails at any point, check the error message and try to fix it. Once fixed, run the script again using ./setup.sh. The script will resume from the point of failure.
5. If you want to run the script from start, use 
    ```bash
    ./setup.sh --reset
    ```

## After Successfull Run

1. ### Setting up RSpec Environment Variables in RubyMine
To ensure your RSpec tests in RubyMine connect to the stack’s database running in Docker, you need to configure the environment variables within RubyMine's run/debug configurations.

- Open Run/Debug Configurations and remove the existing runs from the list to ensure new configurations are applied to all tests going forward.

- Open “Edit configuration templates…”

- Navigate to RSpec in the left-hand panel and open the environment variables.

- Add Environment variables by clicking on “+” sign. These variables are typically used by Rails applications (and thus RSpec tests) to connect to a PostgreSQL database. The values provided here are the defaults for the `tfcdev` PostgreSQL instance.


```
DATABASE_URL: postgres://hashicorp:hashicorp@localhost:25432/hashicorp
REDIS_URL: redis://localhost:26379
TEST_DATABASE_URL: postgres://hashicorp:hashicorp@localhost:25432/hashicorp_test
PGPORT=25432
TEST_REDIS_URL: redis://localhost:26379
VAULT_ADDR: http://127.0.0.1:28200
VAULT_APP: atlas_development
VAULT_TOKEN: atlas
```

2. Open the ngrok url in browser
3. Login with the username `admin` and the password `password123`

## References

- [Getting Started with Atlas Local Backend Development](https://hashicorp.atlassian.net/wiki/spaces/TFENG/pages/2274066581/Getting+Started+with+Atlas+Local+Backend+Development#Install-doormat)
- [How to Generate Artifactory Credentials](https://hashicorp.atlassian.net/wiki/spaces/TFENG/pages/2301854072/How+to+Generate+Artifactory+Credentials)
- [Docker Credential Helper for Internal Artifactory Authentication](https://github.com/hashicorp/docker-credential-doormat)

## Contributing

To contribute to this project, please make a Pull Request with your proposed changes and add Anoop.P1@ibm.com and Aman.Bora@ibm.com as reviewers.