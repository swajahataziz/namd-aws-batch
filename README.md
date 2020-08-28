# Workshop for running Namd on on AWS Batch


* `POSTFIX=$(uuidgen --random | cut -d'-' -f1)`

## Prepare the Docker image

* Download the workshop example code:

    * `git clone https://github.com/swajahataziz/namd-aws-batch`
    * `namd-aws-batch`

* Create the docker image
    * `docker build --tag namd-docker:latest .`

* Create an ECR repository
    * `aws ecr create-repository --repository-name namd-docker-${POSTFIX}`
    * `ECR_REPOSITORY_URI=$(aws ecr describe-repositories --repository-names namd-docker-${POSTFIX} --output text --query 'repositories[0].[repositoryUri]')`

* Push the docker image to the repository:
    * Get login credentials: `aws ecr get-login --no-include-email --region us-east-1`
    * Copy and paste the result from previous command to login
    * `docker tag nextflow:latest $ECR_REPOSITORY_URI`
    * `docker push $ECR_REPOSITORY_URI`
    * Run the following command to get the image details:
    `aws ecr describe-images --repository-name namd-docker-${BUCKET_POSTFIX}`
    * You will need the following information to construct and use the image URI at a later stage
    	* registryId
    	* repositoryName
    	* imageTags
    * The image URI can be constructed using the format `<registryId>.dkr.ecr.<region>.amazonaws.com/<repositoryName>:<imageTag>`


## Configure IAM Policies & Roles

To allow AWS Batch to access the EC2 resources, we need to: 

* Create 3 new Policies:
	* **bucket-access-policy** to allow Batch to access the S3 bucket
	* **ebs-autoscale-policy** to allow the EC2 instance to autoscale the EBS
	* Nextflow needs to be able to create and submit Batch Job Defintions and Batch Jobs, and read workflow logs and session information from an S3 bucket. These permissions are provided via a Job Role associated with the Job Definition. Policies for this role would look like the following:
	* **nextflow-batch-access-policy** to allow Batch jobs to submit other Batch jobs

* and add 3 new Roles:
	* AWSBatchServiceRole
	* ecsInstanceRole
	* BatchJobRole
	
## Access Policies
### Bucket Access Policy

* To configure a new policy
	* In the IAM console, choose **Policies**, **Create policy**
	* Select Service -> S3
	* Select **All Actions**
	* Under **Resources** select **accesspoint** > Any
	* Under **Resources** select **job** > Any	
	* Under **Resources** > bucket, click **Add ARN**
		* Type in the name of the bucket you previously created
		* Click **Add**
	* Under **Resources** > object, click **Add ARN**
		* For **Bucket Name** type in the name of the bucket
		* Click **Object Name**, select **Any**
	* Click Review Policy
	* In the Review Policy Page, enter **bucket-access-policy** in the name field, and click Create Policy.

### EBS Autoscale Policy

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

### Nextflow Batch Job Submission Policy:

* Go to the IAM Console
* Click on **Policies**
* Click on **Create Policy**
* Switch to the **JSON** tab
* Paste the following into the editor:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "batch:DeregisterJobDefinition",
                "batch:SubmitJob",
                "batch:RegisterJobDefinition"
            ],
            "Resource": [
                "arn:aws:batch:*:*:job-definition/nf-*:*",
                "arn:aws:batch:*:*:job-definition/nf-*",
                "arn:aws:batch:*:*:job-queue/*"
            ]
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": [
                "batch:DescribeJobQueues",
                "batch:TerminateJob",
                "batch:CreateJobQueue",
                "batch:DescribeJobs",
                "batch:CancelJob",
                "batch:DescribeJobDefinitions",
                "batch:DeleteJobQueue",
                "batch:ListJobs",
                "batch:UpdateJobQueue"
            ],
            "Resource": "*"
        }
    ]
}
```
* Click **Review Policy**
* Name the policy **nextflow-batch-access-policy**
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
Enabling Read-Only access to all S3 resources is required if you use publicly available datasets such as the [1000 Genomes dataset](https://registry.opendata.aws/1000-genomes/), and others, available in the [AWS Registry of Open Datasets](https://registry.opendata.aws/).


* Type **bucket-access-policy** in the search field for policies
* Click the checkbox next to **bucket-access-policy** to attach the policy
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
	* **bucket-access-policy**
	* **AmazonS3ReadOnlyAccess**
	* **nextflow-batch-access-policy**

* Click **Next: Tags**. (adding tags is optional)
* Click **Next: Review**
* Set the Role Name to **BatchJobRole**
* Click **Create Role**

## Configure AWS ECS Image with NVidia Docker

To be able to run NVidia Docker containers, we need to create a machine image (AMI) based on one of the ECS-Optimised Amazon Linux AMIs and P3.2xlarge instance type, which has a NVidia Tesla V100 with 16GB memory. Please follow the following steps to create an ECS Image with NVidia Docker:

### Setup EC2 Image

1. Go to EC2 Console → Instances → Launch Instance
2. In the search box under “Step 1: Choose an Amazon Machine Image (AMI)” type ECS
3. Select “*Amazon ECS-Optimized Amazon Linux 2 AMI” *from the list
4. Click on Continue when the “Amazon ECS-Optimised Amazon Linux 2 AMI” pricing page pops up
5. Under “Step 2: Choose an Instance Type”, select p3.2xlarge
6. Click Review and Launch → Launch
7. Under ‘Select an existing key pair or create a new key pair’, 
    1. select Choose and existing pair if you already have an EC2 key pair. 
    2. Otherwise select ‘Create new key pair’ from the drop down box and enter a key name under ‘Key pair name’


8. Click on Launch Instances
9. Once the instance has started, use the instance’s public IP to SSH into the instance
10. Once connected to the server, run the following:
`sudo su
 yum update -y
 reboot #in order to update the kernel`

11. SSH into the server once the system has rebooted

`sudo su
 yum install -y gcc wget vim kernel-devel-$(uname -r)
 wget http://us.download.nvidia.com/tesla/450.51.06/NVIDIA-Linux-x86_64-450.51.06.run
 chmod +x NVIDIA-Linux-x86_64-450.51.06.run
 ./NVIDIA-Linux-x86_64-450.51.06.run #follow the installation instructions 
 reboot`

12. SSH into the server once the system has rebooted and run the following:

`sudo nvidia-smi`

13. It should produce a display similar to the following:

![Image of Nvidia Docker](ecs-nvidia.png)

14.  Next we will install nvidia-docker2 and set it up as the default docker runtime. To install nvidia-docker2:

`distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
 curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.repo | \
 sudo tee /etc/yum.repos.d/nvidia-docker.repo
 sudo yum install -y nvidia-docker2 
 sudo pkill -SIGHUP dockerd`

 15. To set Nvidia docker as default runtime

 `sudo vim /etc/docker/daemon.json`

 16. append the following at the beginning of docker deamon config file, *“default-runtime”:”nvidia”.* The resulting document should look as follows:

 `{ *“default-runtime”:”nvidia”*, 
“runtimes”:{ “nvidia”:{ “path”:”/usr/bin/nvidia-container-runtime”, “runtimeArgs”:[] } }
}`

17. Restart docker

`sudo service docker start`

18. Test nvidia-smi with the nvidia cuda image

`docker run --rm nvidia/cuda nvidia-smi`

### Create the AMI

1. Go to the EC2 Console
2. Click on Instances and select the running instance. 
3. Click on Action → Image → Create Image
4. In Image name, enter namd-ami and click Create Image

