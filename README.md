# Prerequisits

The tempaltes and scripts in this repository are designed to be used with PanHandler. For details on how to get PanHandler running see: https://panhandler.readthedocs.io/en/master/running.html

# Usage

Login to Panhandler and navigate to **Panhandler > Import Skillet Repository**.
In the **Repository Name** box, enter **Reference Architecture Automation**.
In the **Git Repository HTTPS URL** box, enter **https://github.com/PaloAltoNetworks/reference_architecture_automation.git**, and then click **Submit**.

Next, you need to create an environment that stores your authentication information. 

At the top right of the page, click the lock icon.
In the **Master Passphrase** box, enter a passphrase, and then click **Submit**.
Navigate to **PalAlto > Create Environment**.
In the **Name** box, enter **AWS**.
In the **Description** box, enter **AWS Environment**, and then click **Submit**.

Next, create the 
In the **Key** box, enter **AWS_ACCESS_KEY_ID**.
In the **Value** box, enter your AWS access key.

In the **Key** box, enter **AWS_SECRET_ACCESS_KEY**.
In the **Value** box, enter your AWS secret.

In the **Key** box, enter **PASSWORD**.
In the **Value** box, enter the password you want the admin user of Panorama and the VM-Series to have.

Click **Load**.

Next, deploy Panorama.
Navigate to **PanHandler > Skillet Collections > Reference Architecture AWS Skillets > Panorama on AWS > Go**.

Next, deploy the Single VPC Design Model
Navigate to **PanHandler > Skillet Modules > Deploy AWS Single VPC > Go**.

Optionally, you can deploy an example application on the infrastructure.
Next, deploy the Single VPC Design Model
Navigate to **PanHandler > Skillet Modules > Deploy an Example Application into the AWS Single VPC > Go**.

# Support

This template/solution is released under an as-is, best effort, support policy. These scripts should be seen as community supported and Palo Alto Networks will contribute our expertise as and when possible. We do not provide technical support or help in using or troubleshooting the components of the project through our normal support options such as Palo Alto Networks support teams, or ASC (Authorized Support Centers) partners and backline support options. The underlying product used (the VM-Series firewall) by the scripts or templates are still supported, but the support is only for the product functionality and not for help in deploying or using the template or script itself. Unless explicitly tagged, all projects or work posted in our GitHub repository (at https://github.com/PaloAltoNetworks) or sites other than our official Downloads page on https://support.paloaltonetworks.com are provided under the best effort policy.

For assistance from the community, please post your questions and comments either to the GitHub page where the solution is posted or on our Live Community site dedicated to public cloud discussions at https://live.paloaltonetworks.com/t5/AWS-Azure-Discussions/bd-p/AWS_Azure_Discussions
