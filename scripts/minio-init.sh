#!/bin/bash

set +o history  
# Server
ALIAS=local
MINIO_SERVER=minio

# Bucket
MINECRAFT_BUCKET=minecraft

# Users and Groups
RESTIC_GROUP=restic-group
CONFIG_GROUP=config-group

# Policies
BACKUP_POLICY_NAME=mc-backup-policy
BACKUP_POLICY_FILE=$(mktemp)
#
CONFIG_POLICY_NAME=mc-config-policy
CONFIG_POLICY_FILE=$(mktemp)

# Create temp dir holding the structure to apply to the bucket
TMP_DIR=$(mktemp -d)
BACKUP_DIR="Backups"
MINECRAFT_DIRS="Datapacks Icons Mods Plugins Worlds"
SUB_DIRS="${BACKUP_DIR} ${MINECRAFT_DIRS}"


# Wait for Minio server to be up
echo "Waiting for ${MINIO_SERVER} ..."
until $(curl --output /dev/null --silent --head --fail http://${MINIO_SERVER}:9000/minio/health/live ); do
    printf '.'
    sleep 1
done
echo "${MINIO_SERVER} is up." 

# Create alias to local minio
mc alias set ${ALIAS} http://${MINIO_SERVER}:9000 ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD}

# Restic part
# Create specific restic user
mc admin user add ${ALIAS} ${RESTIC_USER} ${RESTIC_PASSWORD}
# add user to restic group
mc admin group add ${ALIAS} ${RESTIC_GROUP} ${RESTIC_USER}

# Generate restic backup policy
cat > ${BACKUP_POLICY_FILE} <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Sid": "ListObjectsInBucket",
          "Effect": "Allow",
          "Action": [
              "s3:ListBucket"
          ],
          "Resource": [
              "arn:aws:s3:::${MINECRAFT_BUCKET}"
          ]
      },
      {
          "Sid": "AllObjectActions",
          "Effect": "Allow",
          "Action": [
              "s3:*Object"
          ],
          "Resource": [
              "arn:aws:s3:::${MINECRAFT_BUCKET}/${BACKUP_DIR}/*"
          ]
      }
  ]
}
EOF
cat ${BACKUP_POLICY_FILE}
# Creeate policy
mc admin policy create ${ALIAS} ${BACKUP_POLICY_NAME} ${BACKUP_POLICY_FILE}
# Attach backup policy to backup group
mc admin policy attach ${ALIAS} ${BACKUP_POLICY_NAME}  --group ${RESTIC_GROUP}

#
# ReConfigstic part
# Create specific config user
mc admin user add ${ALIAS} ${CONFIG_USER} ${CONFIG_PASSWORD}
# add user to restic group
mc admin group add ${ALIAS} ${CONFIG_GROUP} ${CONFIG_USER}

# Create policy for each config sub dirs
# Header
cat > ${CONFIG_POLICY_FILE} <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
EOF
# Individual resources
for resource in ${MINECRAFT_DIRS}
do 
  cat >> ${CONFIG_POLICY_FILE} <<EOF
        {
            "Sid": "PutObject${resource}",
            "Effect": "Allow",
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${MINECRAFT_BUCKET}/${resource}/*"
        },
EOF
done
# Adding List to give GUI user visibility
cat >> ${CONFIG_POLICY_FILE} <<EOF
    {
            "Sid": "List${BACKUP_DIR}",
            "Effect": "Allow",
            "Action": ["s3:ListBucket"],
            "Resource": "arn:aws:s3:::${MINECRAFT_BUCKET}/*"
    }
  ]
}
EOF
#
cat ${CONFIG_POLICY_FILE}
mc admin policy create ${ALIAS} ${CONFIG_POLICY_NAME} ${CONFIG_POLICY_FILE}
# Attach config policy
mc admin policy attach ${ALIAS} ${CONFIG_POLICY_NAME} --group config-group


# Create service account for restic
mc admin user svcacct add                       \
   --access-key "${AWS_ACCESS_KEY_ID}"          \
   --secret-key "${AWS_SECRET_ACCESS_KEY}"  \
   ${ALIAS} ${RESTIC_USER}

# Create bucket for Minecraft
mc mb ${ALIAS}/${MINECRAFT_BUCKET}
# Restric bucket access permissions
mc anonymous --recursive set download ${ALIAS}/${MINECRAFT_BUCKET}
# Create structure locally
for sd in ${SUB_DIRS};
do
  mkdir -p ${TMP_DIR}/${sd} && touch ${TMP_DIR}/${sd}/README
done
# Copy structure to bucket
mc cp --recursive ${TMP_DIR}/ ${ALIAS}/${MINECRAFT_BUCKET}
#
set -o history 
exit 0