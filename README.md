# Workshop for running Namd on on AWS Batch
------------------------

This workshop assumes that you run in the AWS N. Virigia region (us-east-1)

## Workshop Setup
------------------------

* Login to AWS Console

## Create a Cloud9 Instance
------------------------

AWS Cloud9 is a cloud-based integrated development environment (IDE) that lets you write, run, and debug your code with just a browser. This workshop uses Cloud9 to introduce you to the AWS Command Line Interface (AWS CLI) without the need to install any software on your laptop.

This workshop assumes that you are using the AWS us-east-1 (North Virginia) Region. Please, select the right Region from the AWS Console.

To launch the Cloud9 IDE:

* In the AWS Management Console, locate **Cloud9** by using the search bar

![Image of Console](/images/cloud9-find.png)

* Choose **Create Environment**
* Name your environment **MyHPCLabEnv** and choose **Next Step**
* On the **Configure Settings** page, locate **Cost-saving setting** drop-down menu, choose **After a day**
* Choose Next Step.
* Choose **Create Environment**

Your AWS Cloud9 instance will be ready in a few minutes.
![Image of Cloud9 starting page](/images/cloud9-create.png)

Once your Cloud9 instance is up and running:

* In the AWS Management Console, locate **EC2** by using the search bar, or choose **Services**, then **EC2**
* Go to **Elastic Block Storage** -> **Volumes**
* Choose the EBS Volume for your Cloud9 environment

![Image of EBS Console](/images/EBS.png)

* Select **Actions** -> **Modify Volume** ##this is no longer here
* Increase the size to 30GB
* Click **Modify**
* Under **Are you sure that you want to modify volume vol-xxxxxxx?** Click Yes
* run the following commands on the cloud9 terminal

```bash
    sudo growpart /dev/xvda 1
```

```bash
    sudo xfs_growfs /dev/xvda1
```

### Clone the github repo
* Open the Cloud9 terminal
* Enter the following command to download the workshop example code:

```bash
    git clone https://github.com/swajahataziz/namd-aws-batch.git
```

* Switch to the source code directory as the working directory:

```bash
    cd namd-aws-batch
```

### Create ECR Repository

Amazon Elastic Container Registry (Amazon ECR) is an AWS managed container image registry service that is secure, scalable, and reliable. Amazon ECR supports private container image repositories with resource-based permissions using AWS IAM. This is so that specified users or Amazon EC2 instances can access your container repositories and images. You can use your preferred CLI to push, pull, and manage Docker images, Open Container Initiative (OCI) images, and OCI compatible artifacts.

Amazon ECR is used by a number of AWS services such as Amazon SageMaker, AWS Batch and Amazon ECS to retrieve and deploy containers for their workloads. In this workshop, we will be using ECR as a container repository to store the NAMD container, which AWS Batch will used to retrieve and execute a job.

To create an ECR repository, run the following:

* Generate a random postfix to be used to name the repository

```bash
    POSTFIX=$(uuidgen --random | cut -d'-' -f1)
```

* Create the ECR repository using the AWS CLI

```bash
    aws ecr create-repository --repository-name namd-docker-${POSTFIX}
```

* Get the ECR respository URI

```bash
    ECR_REPOSITORY_URI=$(aws ecr describe-repositories --repository-names namd-docker-${POSTFIX} --output text --query 'repositories[0].[repositoryUri]')
```

### Build the docker image
Next, we will build the docker image and push it to the ECR repository.

* Run the following command to build the docker image

```bash
    docker build --tag $ECR_REPOSITORY_URI .
```

### Push Docker Image to ECR

* Get login credentials: 
    ```bash
    $(aws ecr get-login --no-include-email --region us-east-1)
    ```
* Push the docker image to the repository:

    ```bash
    docker push $ECR_REPOSITORY_URI
    ```
* Run the following command to get the image details:

    ```bash
    aws ecr describe-images --repository-name namd-docker-${POSTFIX}
    ```
* You will need the following information to construct and use the image URI at a later stage
    * registryId
    * repositoryName
    * imageTags
* The image URI can be constructed using the format `<registryId>.dkr.ecr.<region>.amazonaws.com/<repositoryName>:<imageTag>`

### Create an S3 Bucket:

You will need an S3 bucket to store the results of your NAMD simulation. Follow the below instructions to create the S3 bucket:

```bash
aws s3 mb s3://namd-workshop-${POSTFIX}
```

Take note of the bucket name you have just created

## Setting up IAM Roles & Policies

To allow AWS Batch to access the EC2 resources, we need to: 

* Create a **ebs-autoscale-policy** to allow the EC2 instance to autoscale the EBS

* and add the following 3 new Roles:
    * AWSBatchServiceRole
    * ecsInstanceRole
    * BatchJobRole
    
## EBS Autoscale Policy

* Go to the IAM Console
![IAM Console](/images/IAM-console.png)
* Click on **Policies** -> **Create Policy** 
![Create Policy](/images/create-policy.png)
* Switch to the **JSON** tab
![Json Policy](/images/json-policy.png)
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
* In the Review Policy Page, enter **ebs-autoscale-policy** under **Name**
* Click **Create Policy**

## IAM Roles

### Create a Batch Service Role

* In the IAM console, choose **Roles** -> **Create Role**.
![Create Role](/images/create-role.png)
* Under type of trusted entity, choose **AWS service** then **Batch**.
* Click **Next: Permissions**.
![Batch Permissions](/images/batch-permissions.png)
* On the Attach Policy page, the **AWSBatchServiceRole** will already be attached
* Click Next:Tags (adding tags is optional)
* Click **Next: Review**
* In the Review Page, enter **AWSBatchServiceRole** under **Name** and click on **Create Role**

### Create an EC2 Instance Role

This is a role that controls what AWS Resources EC2 instances launched by AWS Batch have access to. In this case, you will limit S3 access to just the bucket you created earlier.

* Go to the IAM Console
* Click on **Roles**
* Click on **Create Role**
* Select **AWS service** as the trusted entity
![Select AWS Service](/images/create-role-aws-service.png)
* Choose **EC2** from the larger services list
* Choose **EC2 - Allows EC2 instances to call AWS services on your behalf** as the use case.
![Create EC2 Role](/images/create-role-ec2.png)
* Click **Next: Permissions**
* Type **ContainerService** in the search field for policies
* Click the checkbox next to **AmazonEC2ContainerServiceforEC2Role** to attach the policy
![Container Service Permissions](/images/container-permissions.png)
* Type **S3** in the search field for policies
* Click the checkbox next to **AmazonS3ReadOnlyAccess** to attach the policy
![S3 Permissions](/images/s3-permissions.png)
**Note** :
Enabling Read-Only access to all S3 resources is required if you use publicly available datasets such as the ones available in the [AWS Registry of Open Datasets](https://registry.opendata.aws/).
* Type **ebs-autoscale-policy** in the search field for policies
* Click the checkbox next to **ebs-autoscale-policy** to attach the policy
![EBS Autoscale Policy](/images/ebs-autoscale.png)
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
![ECS Permission](/images/ecs-role.png)
* Choose **Elastic Container Service Task** as the use case.
![ECS Task Permission](/images/ecs-task-permissions.png)
* Click **Next: Permissions**
* Attach the following policies.
    * **AmazonS3ReadOnlyAccess**
![S3 Permissions](/images/s3-permissions.png)
* Click **Next: Tags**. (adding tags is optional)
* Click **Next: Review**
* Set the Role Name to **BatchJobRole**
* Click **Create Role**

#### About EFA

An Elastic Fabric Adapter (EFA) is a network device that you can attach to your Amazon EC2 instance to accelerate High Performance Computing (HPC) and machine learning applications. EFA enables you to achieve the application performance of an on-premises HPC cluster, with the scalability, flexibility, and elasticity provided by the AWS Cloud.

EFA provides lower and more consistent latency and higher throughput than the TCP transport traditionally used in cloud-based HPC systems. It enhances the performance of inter-instance communication that is critical for scaling HPC and machine learning applications. It is optimized to work on the existing AWS network infrastructure and it can scale depending on application requirements.

EFA integrates with Libfabric 1.11.1 and it supports Open MPI 4.0.5 and Intel MPI 2019 Update 7 for HPC applications, and Nvidia Collective Communications Library (NCCL) for machine learning applications.

We will demonstrate the setup and use of EFA in the context of AWS Batch.

#### Prepare an EFA-enabled Security Group

An EFA requires a security group that allows all inbound and outbound traffic to and from the security group itself.

To create an EFA-enabled security group

1. Open the Amazon EC2 console at https://console.aws.amazon.com/ec2/
2. In the navigation pane, choose Security Groups and then choose Create Security Group.
![Create Security Group](/images/create-security-group.png)
3. In the Create Security Group window, do the following:
    * For Security group name, enter a descriptive name for the security group, such as efa-enabled-sg.
    * (Optional) For Description, enter a brief description of the security group.
    * For VPC, select the VPC into which you intend to launch your EFA-enabled instances.
    * Choose Create.
![Create Security Group](/images/create-sg-page2.png)
4. Select the security group that you created, and on the Description tab, copy the Group ID.
5. On the Inbound tab, do the following:
    * Click on 'Edit Inbound Rules'.
    * For Type, choose All traffic.
    * For Source, choose Custom and paste the security group ID that you copied into the field.
    * Choose Save.
![Create Security Group](/images/sg-edit-inbound.png)
![Create Security Group](/images/sg-edit-inbound-2.png)
6. On the Outbound tab, do the following:
    * Click on 'Edit Outbound Rules'.
    * For Type, choose All traffic.
    * For Destination, choose Anywhere.
    * Choose Save.
![Create Security Group](/images/sg-edit-outbound.png)

#### Create an EFA Placement Group

To ensure optimal physical locality of instances, we create a [placement group](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/placement-groups.html#placement-groups-cluster), with strategy `cluster`.

1. Open the Amazon EC2 console at https://console.aws.amazon.com/ec2/
2. In the navigation pane, choose Placement Groups and then choose Create Placement Group.
![Create Placement Group](/images/create-placement-group.png)
3. In the **Create Placement Group** page, enter efa under **Name** and select **Cluster** from the **Placement Strategy** drop down
4. Click on **Create group** button
![Create Placement Group](/images/create-placement-group-2.png)

Alternatively, you can run the following command in your Cloud9 terminal:
```bash
aws ec2 create-placement-group --group-name "efa" --strategy "cluster" --region [your_region]
```

#### About EC2 Launch Templates

A launch template is an instance configuration template that can be used to launch EC2 instances. Included in a launch template are the ID of the Amazon Machine Image (AMI), the instance type, a key pair, security groups, and the other parameters that you use to launch EC2 instances. Defining a launch template allows you to have multiple versions of a template. With versioning, you can create a subset of the full set of parameters and then reuse it to create other templates or template versions. For example, you can create a default template that defines common configuration parameters and allow the other parameters to be specified as part of another version of the same template.

For this workshop, we will create a launch template, which we will use to set up the AWS Batch compute environment. We are using the launch template because we need an additional mount point (scratch) to store the results of our NAMD executions. 

#### Create a Launch Template


To create an EC2 Launch template:

1. Open the Amazon EC2 console at https://console.aws.amazon.com/ec2/
2. In the navigation pane, choose Launch Template and then choose Create launch template.
![Create Launch Template](/images/launch-template-console.png)
3. In the Create launch template window, do the following:
    * For Launch template name, enter a descriptive name for the security group, such as namd-batch-lt.
    * (Optional) For Description, enter a brief description of the launch template.
    * Under Amazon machine image (AMI), select the `AMI` drop down and paste in the following AMI id: `ami-00efed235165d14b2` 
    ![AMI Selection Dropdown](/images/lt-ami-dropdown.png)
    * You will see a single search result named `amzn2-ami-ecs-gpu-hvm-2.0.20210202-x86_64-ebs`. Select that AMI. This is an ECS optimised AMI with built-in support for running ECS/Docker containers on EC2 on GPU instances (which we require for NAMD).
    ![AMI Search Result](/images/lt-ami-search.png)
    * Under **Storage(volumes)**, select **Add new volume**
    * Under **Device name** select **General purpose SSD (gp2)**
    ![AMI Storage](/images/lt-storage.png)
    * Under **Advanced details** in user data, paste the following text:
    ```bash
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="==MYBOUNDARY=="

    --==MYBOUNDARY==
    Content-Type: text/cloud-config; charset="us-ascii"

    runcmd:
    - yum –exclude=nvidia* update -y
    - mkfs -t ext4 /dev/sdb
    - mkdir /scratch
    - echo -e '/dev/sdb\t/scratch\text4\tdefaults\t0\t0' | sudo tee -a /etc/fstab
    - mount /scratch

    --==MYBOUNDARY==--
    ``` 
    * Choose Create launch template.
4. Copy the launch template id. You will need it when you will create the compute environment in AWS Batch

Next, we'll create all the necessary AWS Batch resources.

* Go to the Cloud9 development enviroment you previously created and open the Cloud9 terminal
* Switch to the batch-resources folder
```bash
cd batch-resources/
```

First we'll create the compute environment, this defines the instance type, subnet and IAM role to be used. Open the **compute_environment.json** file in a text editor. The following sections in the compute environment config file are of interest:

* minVCPUs: set to 0
* maxvCPUs: set to 96
* launchTemplateId: here you will have to replace `<enter launch template id of the namd lt>` with the value of launch template id you copied during the launch template configuration step. 
* instanceTypes: where we have selected the p3dn.24xlarge instances, which provide GPU and EFA capabilities 
* subnets: here you will have to replace `<enter-subnet-id>` with that of a subnet id from your VPC. 
* securityGroupIds: replace `<enter-security-group-id>` with the id of the security group that you set up in previous steps
* instance role: This is the IAM role an EC2 instance launched by AWS Batch will use to interact with other services when executing jobs. Make sure you replace the `<account-id>` in the ARN with your own account-id.
* serviceRole: Make sure you replace the `<account-id>` in the service role ARN with your own account-id.

Run the following command to create the compute environment:


```bash
aws batch create-compute-environment --cli-input-json file://compute_environment.json
```

Next, we need a job queue to point to the compute environment, run the following command in the terminal:

```bash
aws batch create-job-queue --cli-input-json file://job_queue.json
```


### Job Definition

Open the **job_definition.json** in your Cloud9 environment. AWS Batch requires a job definition, which defines which docker image to use for the job. Additionally, the job definition configuration file also defines a path between a host mount point and container directory (/scratch), which will be used to temporarily store the results from the simulation before they are copied over to S3. Finally, the file also specifies the following environment variables, which will be used by the job:

* SCRATCH_DIR
* OMP_THREADS
* MPI_THREADS
* S3_OUTPUT: Please make sure to replace `<Enter address of your S3 bucket>` with the address of the S3 bucket you created during setup. 

Edit the `<image-full-name>` and `<account-id>` sections of the **job_definition.json** with the pertinent information. You can get the image full name through the AWS Elastic Container Repository Console:

```bash
aws batch register-job-definition --cli-input-json file://job_definition.json
```
which should return a response similar to this:
```
{
    "jobDefinitionArn": "arn:aws:batch:us-east-1:<account-id>:job-definition/namd-job-definition:1",
    "jobDefinitionName": "namd-job-definition",
    "revision": 1
}
```

Finally we can submit a job!

```bash
aws batch submit-job --region ${AWS_REGION} --job-name example-namd-job --job-queue namd-job-queue --job-definition namd-job-definition
```

Once we submit a job, AWS Batch performs the following actions:

* Create an ECS cluster in **Elastic Container Service** for the AWS Batch Compute Environment, if one doesn't already exists. You can check this in AWS Console by navigating to Elastic Container Service 
* Create an auto-scaling group in EC2 for the compute environment. You can verify this has been done for your job/compute environment by navigating to EC2 -> Auto Scaling -> Auto Scaling Groups in your AWS Console. You will find an Auto Scaling group with a naming convention `<compute environment name>-<uuid>`. Please note it may take AWS Batch a few minutes to create the auto-scaling group
* Once the ECS cluster and Auto Scaling group are created, start an EC2 instance, at which point, ECS will launch the docker container/task on AWS Batch's behalf. 
* The docker container in our example will execute a script named `entry-point.sh`, which does the following:
    - Launches a supervisord process based on a config stored in the container (`/etc/supervisor/supervisord.conf`)
    - The **supervisord** process launches an MPI program using `/supervised-scripts/mpi-run.sh`
    - The MPI program calls the namd process and submits the required files for executing the APOA1 benchmark. After NAMD execution is complete, it saves the simulation results to the S3 path, as defined in the **$S3_OUTPUT** environment variable 

Once you have submited your job to AWS Console, you can monitor the progress of your job in AWS Console. To monitor the job:
* Open the AWS Batch console
![Batch Console](/images/batch-console.png)
* Go to **Jobs** and select the Job queue you previously created from the job queue drop down
![Batch Dashboard](/images/batch-job-view.png)
* This will display the currently running jobs in the queue and their status. You can continue to monitor the progress of your job here
![Job Status View](/images/job-status.png)

Additionally, as explained before, you can also check the progress of background artefacts being created by services that work with AWS Batch, as explained in the previous section. Finally, you can also check out detailed execution logs of your job in CloudWatch. Please note, it may take a couple of minutes after your job execution starts before the relevant logs appear in CloudWatch. To check out the logs:
* Opn the AWS CloudWatch console:
* Go to **Logs** -> **Log groups**
* Under Log groups, select */aws/batch/job* and select the latest log stream with the naming convention *<job-definition-name>/default/uuid*

Once, your job execution has successfully completed:
* Go to S3 console
* Navigate to the S3 bucket you specified in the **$S3-OUTPUT** environment variable
* You should see a tar.gz file under the prefix **namd-output** with a name similar to **batch_output_<uuid>.tar.gz**. You can now download the file and evaluate the results.
