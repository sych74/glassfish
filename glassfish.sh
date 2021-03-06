#!/bin/bash

start() {
    
    ~/glassfish4/bin/asadmin start-domain

    # Create Cluster
    if [ -n "${DAS}" ]
    then
    	ssh-keygen  -t rsa -b 4096 -q -N '' -f ~/.ssh/id_rsa
    	cp ~/.ssh/id_rsa.pub ~/.ssh/authorized_keys

        ~/glassfish4/bin/asadmin --user=admin --passwordfile=${PSWD_FILE} --interactive=false create-cluster cluster1
        ~/glassfish4/bin/asadmin --user=admin stop-domain
        ~/glassfish4/bin/asadmin start-domain -v
    fi
    if [ -n "${DAS_PORT_4848_TCP_ADDR}" ]
    then
        # Create cluster node
        ~/glassfish4/bin/asadmin --user=admin --passwordfile=${PSWD_FILE} --interactive=false \
        --host das --port 4848 create-local-instance --cluster cluster1 cluster1-"${HOSTNAME}"

        # Stop domain
        ~/glassfish4/bin/asadmin --user=admin stop-domain

        # Getting all keys from Domain Administration Server SSH
        ssh-keyscan -H das >> ~/.ssh/known_hosts

        # Busy waiting for SSH to be enabled
        SSH_STATUS=$(ssh ${USER}@das echo "I am waiting.")
        echo $SSH_STATUS >> /var/log/run.log
        while [ "${SSH_STATUS}" = "ssh: connect to host das port 22: Connection refused" ]
        do
            sleep 20
            SSH_STATUS=$(ssh ${USER}@das echo "I am waiting.")
            echo $SSH_STATUS >> /var/log/run.log
        done

        # Busy waiting for Domain Administration Server to be available
        DAS_STATUS=$(ssh ${USER}@das ~/glassfish4/glassfish/bin/asadmin --user=admin \
        --passwordfile=${PSWD_FILE} list-domains | head -n 1)

        while [ "${DAS_STATUS}" = "domain1 not running" ]
        do
            sleep 20
            DAS_STATUS=$(ssh ${USER}@das ~/glassfish4/glassfish/bin/asadmin --user=admin \
            --passwordfile=${PSWD_FILE} list-domains | head -n 1)
        done

        # Get node own LAN IP
        NODEHOST_ENTRY=$(cat /etc/hosts | grep "${HOSTNAME}")
        export HOST_IP=$(echo "${NODEHOST_ENTRY}" | cut -f1 -s)
        if [ -z "${HOST_IP}" ]
            then export HOST_IP=$(echo "${NODEHOST_ENTRY}" | cut -d' ' -f1)
        fi

        # Update existing CONFIG node to a SSH one
        ssh ${USER}@das ~/glassfish4/glassfish/bin/asadmin --user=admin \
        --passwordfile=${PSWD_FILE} --interactive=false update-node-ssh \
        --sshuser "${USER}" --sshkeyfile ~/.ssh/id_rsa \
        --nodehost "${HOST_IP}" --installdir "${HOME_DIR}"/glassfish4 "${HOSTNAME}"

        # Start instance
        ssh ${USER}@das ~/glassfish4/glassfish/lib/nadmin --user=admin \
        --passwordfile=${PSWD_FILE} --interactive=false start-instance cluster1-"${HOSTNAME}"

        while [[ true ]]; do
            sleep 1
        done
    fi
}

stop() {
    
    ssh ${USER}@das ~/glassfish4/glassfish/lib/nadmin --user=admin \
    --passwordfile=${PSWD_FILE} --interactive=false stop-instance cluster1-"${HOSTNAME}"

    ssh ${USER}@das ~/glassfish4/glassfish/lib/nadmin --user=admin \
    --passwordfile=${PSWD_FILE} --interactive=false delete-instance cluster1-"${HOSTNAME}"

    ssh ${USER}@das ~/glassfish4/glassfish/bin/asadmin --user=admin \
    --passwordfile=${PSWD_FILE} --interactive=false delete-node-ssh "${HOSTNAME}"

    ~/glassfish4/glassfish/lib/nadmin --user=admin --passwordfile=${PSWD_FILE} \
    --interactive=false delete-local-instance --node "${HOSTNAME}" cluster1-"${HOSTNAME}"
}

case ${1} in
    start)
        start
        ;;
    stop)
        stop
        ;;
esac
