# ATLAS SETUP AUTOMATION

What is Atlas?

Atlas is a full-stack Rails/Ember application that powers HCP Terraform (formerly Terraform Cloud) at https://app.terraform.io. It provides both the backend API (Ruby on Rails + PostgreSQL) and frontend UI (Ember.js) for managing Terraform infrastructure workflows, supporting both cloud (SaaS) and self-hosted (Enterprise) deployments.

## PREREQUISITES

- Download [Docker Desktop](https://docs.docker.com/desktop/setup/install/mac-install/) and move it to Applications folder.
- Request access to Hashicorp Okta and Hashicorp Okta Certificate using [IBM AccessHub](https://ibm-support.saviyntcloud.com/ECMv6/request/requestHome).
- Once the access is granted log into Artifactory through your Okta dashboard.
- Request pull access to artifactory-users group which will also add the Artifactory tile to Okta.
    - Go to doormat -> App Access -> Request Access
    - Choose Artifactory Application from drop down menu
    - Request for artifactory-users group
    - Provide a justification and click submit
  ![Requesting access to artifactory-users](images/doormat1.png)
- User should have a github account with access to the hashicorp organization. (Consult your Engineering Manager for more information getting access)
- Once your Github account gets activated, request access to following teams
    - ["core" team](https://passport.hashicorp.services/namespaces/doormat/groups/github-access-core)
    - [“terraform-enterprise” team ](https://passport.hashicorp.services/namespaces/doormat/groups/github-hashicorp-team-terraform-enterprise)
- If you are doing the setup from home, make sure that VPN is disconnected and IPv6 is disabled in your system.
    -   Go to System Settings-> Network-> WiFi
    -   Click Details and go to TCP/IP
    -   Change Configure options to 'link-local only'

[Note]: Once the setup is complete, make sure to enable IPv6 in your system.

[Note]: Access requests may take 2-3 hours to become effective. Run the script 2-3 hours after completing the prerequisites.

## SETUP

1.  Clone the repository and navigate to the Atlas-backend-setup-automation folder
2.  ```bash
    chmod +x setup.sh
    ```
3.  ```bash
    ./setup.sh
    ```
4.  If script fails at any point, check the error message and try to fix it. Once fixed, run the script again using ./setup.sh. The script will resume from the point of failure.
5.  If you want to run the script from start, use
    ```bash
    ./setup.sh --reset
    ```

## After Successfull Run

1. Open the ngrok url in browser
2. Login with the username `admin` and the password `password123`

## References

- [Getting Started with Atlas Local Backend Development](https://hashicorp.atlassian.net/wiki/spaces/TFENG/pages/2274066581/Getting+Started+with+Atlas+Local+Backend+Development#Install-doormat)
- [How to Generate Artifactory Credentials](https://hashicorp.atlassian.net/wiki/spaces/TFENG/pages/2301854072/How+to+Generate+Artifactory+Credentials)
- [Docker Credential Helper for Internal Artifactory Authentication](https://github.com/hashicorp/docker-credential-doormat)

## Contributing

We welcome contributions to this project. To submit your changes:

1. Create a Pull Request with your proposed modifications
2. Add Anoop.P2@ibm.com and Aman.Bora@ibm.com as reviewers

For questions or support, feel free to reach out to us on Slack.
