# Workshop for running Namd on on AWS Batch
------------------------

This workshop assumes that you run in the AWS N. Virigia region (us-east-1)

## Workshop Setup
------------------------

* Login to the Event Engine

    * `https://dashboard.eventengine.run/dashboard`

## Create a Cloud9 Instance
------------------------

AWS Cloud9 is a cloud-based integrated development environment (IDE) that lets you write, run, and debug your code with just a browser. This workshop uses Cloud9 to introduce you to the AWS Command Line Interface (AWS CLI) without the need to install any software on your laptop.

AWS Cloud9 contains a collection of tools that let you code, build, run, test, debug, and release software in the cloud using your internet browser. The IDE offers support for python, pip, AWS CLI, and provides easy access to AWS resources through Identity and Access Management (IAM) user credentials. The IDE includes a terminal with sudo privileges to the managed instance that is hosting your development environment and a pre-authenticated CLI. This makes it easy for you to quickly run commands and directly access AWS services.

To launch the Cloud9 IDE:

* In the AWS Management Console, locate **Cloud9** by using the search bar, or choose **Services**, then **Cloud9**

![Image of Console](cloud9-find.png)

* Choose **Create Environment**
* Name your environment **MyHPCLabEnv** and choose **Next Step**
* On the **Configure Settings** page, locate **Cost-saving setting** drop-down menu, choose **After a day**
* Choose Next Step.
* Choose **Create Environment**

Your AWS Cloud9 instance will be ready in a few minutes.
![Image of Cloud9 starting page](cloud9-create.png)

Once your Cloud9 instance is up and running:

* In the AWS Management Console, locate **EC2** by using the search bar, or choose **Services**, then **EC2**
* Go to **Elastic Block Storage** -> **Volumes**
* Choose the EBS Volume for your Cloud9 environment

![Image of EBS Console](EBS.png)

* Select **Actions** -> **Modify Volume**
* Increase the size to 30GB
* Click **Modify**
* Under **Are you sure that you want to modify volume vol-xxxxxxx?** Click Yes
* run the following commands on the cloud9 terminal
 `sudo growpart /dev/xvda 1`
 `sudo xfs_growfs /dev/xvda1`


## Prepare the Docker image

* Open the Cloud9 terminal
* Enter the following command to download the workshop example code:

    * `git clone https://github.com/swajahataziz/namd-aws-batch.git`

* Switch to the source code directory as the working directory:

    * `cd namd-aws-batch`

* Create the docker image

    * `docker build --tag namd-docker:latest .`

* Create an ECR repository

    * `POSTFIX=$(uuidgen --random | cut -d'-' -f1)`
    * `aws ecr create-repository --repository-name namd-docker-${POSTFIX}`
    * `ECR_REPOSITORY_URI=$(aws ecr describe-repositories --repository-names namd-docker-${POSTFIX} --output text --query 'repositories[0].[repositoryUri]')`

* Push the docker image to the repository:
    * Get login credentials: 
        * `$(aws ecr get-login --no-include-email --region us-east-1)`
        * `docker tag namd-docker:latest $ECR_REPOSITORY_URI`
        * `docker push $ECR_REPOSITORY_URI`
    * Run the following command to get the image details:

        * `aws ecr describe-images --repository-name namd-docker-${POSTFIX}`
    * You will need the following information to construct and use the image URI at a later stage
        * registryId
        * repositoryName
        * imageTags
    * The image URI can be constructed using the format `<registryId>.dkr.ecr.<region>.amazonaws.com/<repositoryName>:<imageTag>`


## Configure IAM Policies & Roles

To allow AWS Batch to access the EC2 resources, we need to: 

* Create a **ebs-autoscale-policy** to allow the EC2 instance to autoscale the EBS

* and add 3 new Roles:
    * AWSBatchServiceRole
    * ecsInstanceRole
    * BatchJobRole
    * ecsTaskExecutionRole
    
## EBS Autoscale Policy

* Go to the IAM Console
* Click on **Policies**
* Click on **Create Policy**
* Switch to the **JSON** tab
* Paste the following into the editor:
```json
{
    "Version": "2012-10-17",
    "Statement": {
        "Action": [
            "ec2:*Volume",
            "ec2:modifyInstanceAttribute",
            "ec2:describeVolumes"
        ],
        "Resource": "*",
        "Effect": "Allow"
    }
}
```
* Click **Review Policy**
* Name the policy **ebs-autoscale-policy**
* Click **Create Policy**

## IAM Roles

### Create a Batch Service Role

* In the IAM console, choose **Roles**, **Create New Role**.
* Under type of trusted entity, choose **AWS service** then **Batch**.
* Click **Next: Permissions**.
* On the Attach Policy page, the **AWSBatchServiceRole** will already be attached
* Click Next:Tags (adding tags is optional)
* Click **Next: Review**
* Set the Role Name to **AWSBatchServiceRole**, and choose Create Role.

### Create an EC2 Instance Role

This is a role that controls what AWS Resources EC2 instances launched by AWS Batch have access to. In this case, you will limit S3 access to just the bucket you created earlier.

* Go to the IAM Console
* Click on **Roles**
* Click on **Create Role**
* Select **AWS service** as the trusted entity
* Choose **EC2** from the larger services list
* Choose **EC2 - Allows EC2 instances to call AWS services on your behalf** as the use case.
* Click **Next: Permissions**
* Type **ContainerService** in the search field for policies
* Click the checkbox next to **AmazonEC2ContainerServiceforEC2Role** to attach the policy
* Type **S3** in the search field for policies
* Click the checkbox next to **AmazonS3ReadOnlyAccess** to attach the policy


**Note** :
Enabling Read-Only access to all S3 resources is required if you use publicly available datasets such as the ones available in the [AWS Registry of Open Datasets](https://registry.opendata.aws/).


* Type **ebs-autoscale-policy** in the search field for policies
* Click the checkbox next to **ebs-autoscale-policy** to attach the policy
* Click **Next: Tags**. (adding tags is optional)
* Click **Next: Review**
* Set the Role Name to **ecsInstanceRole**
* Click **Create role**

### Create a Job Role

This is a role used by individual Batch Jobs to specify permissions to AWS resources in addition to permissions allowed by the Instance Role above.

* Go to the IAM Console
* Click on **Roles**
* Click on **Create role**
* Select **AWS service** as the trusted entity
* Choose **Elastic Container Service** from the larger services list
* Choose **Elastic Container Service Task** as the use case.
* Click **Next: Permissions**

* Attach the following policies.
    * **AmazonS3ReadOnlyAccess**

* Click **Next: Tags**. (adding tags is optional)
* Click **Next: Review**
* Set the Role Name to **BatchJobRole**
* Click **Create Role**


## Setup Security and Placement Groups

### Prepare an EFA-enabled Security Group

An EFA requires a security group that allows all inbound and outbound traffic to and from the security group itself.

To create an EFA-enabled security group

1. Open the Amazon EC2 console at https://console.aws.amazon.com/ec2/
2. In the navigation pane, choose Security Groups and then choose Create Security Group.
3. In the Create Security Group window, do the following:

    * For Security group name, enter a descriptive name for the security group, such as efa-enabled-sg.

    * (Optional) For Description, enter a brief description of the security group.

    * For VPC, select the VPC into which you intend to launch your EFA-enabled instances.

    * Choose Create.

4. Select the security group that you created, and on the Description tab, copy the Group ID.
5. On the Inbound tab, do the following:

    * Click on 'Edit Inbound Rules'.

    * For Type, choose All traffic.

    * For Source, choose Custom and paste the security group ID that you copied into the field.

    * Choose Save.

6. On the Outbound tab, do the following:

    * Click on 'Edit Outbound Rules'.

    * For Type, choose All traffic.

    * For Destination, choose Anywhere.

    * Choose Save.

### Create an EFA Placement Group

To ensure optimal physical locality of instances, we create a [placement group](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/placement-groups.html#placement-groups-cluster), with strategy `cluster`.

```bash
aws ec2 create-placement-group --group-name "efa" --strategy "cluster" --region [your_region]
```

## AWS Batch Resources

Next, we'll create all the necessary AWS Batch resources.

```bash
cd batch-resources/
```

First we'll create the compute environment, this defines the instance type, subnet and IAM role to be used. Edit the `<enter-subnet-id>`, `<enter-security-group-id>` and `<account-id>` sections with the pertinent information. Then create the compute environment:


```bash
aws batch create-compute-environment --cli-input-json file://compute_environment.json
```

Next, we need a job queue to point to the compute environment:

```bash
aws batch create-job-queue --cli-input-json file://job_queue.json
```


### Job Definition

Now we need a job definition, this defines which docker image to use for the job. Edit the `<image-full-name>` and `<account-id>` sections with the pertinent information. You can get the image full name through the AWS Elastic Container Repository Console:

```bash
aws batch register-job-definition --cli-input-json file://job_definition.json
{
    "jobDefinitionArn": "arn:aws:batch:us-east-1:<account-id>:job-definition/namd-job-definition:1",
    "jobDefinitionName": "namd-job-definition",
    "revision": 1
}
```

### Submit a job

Finally we can submit a job!

```bash
aws batch submit-job --region ${AWS_REGION} --job-name example-namd-job --job-queue namd-job-queue --job-definition namd-job-definition
```