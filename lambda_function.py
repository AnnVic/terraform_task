import boto3

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    regions = [region['RegionName'] for region in ec2.describe_regions()['Regions']]
    
    for region in regions:
        ec2 = boto3.client('ec2', region_name=region)
        response = ec2.describe_instances(
            Filters=[
                {'Name': 'tag:Name', 'Values': ['AutoStop']},
                {'Name': 'instance-state-name', 'Values': ['running']},
            ]
        )

        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_id = instance['InstanceId']
                ec2.stop_instances(InstanceIds=[instance_id])
                print(f"Stopped instance {instance_id} in {region}")
