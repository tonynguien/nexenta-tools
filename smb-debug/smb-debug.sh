#!/bin/bash
#
# smb-debug.sh
#
# Collects logs useful when troubleshooting smb issues.
#

# Command line args
IFACE=$1

# Dtrace
SMBSRV="/usr/lib/smbsrv/dtrace/smbsrv.d"
AUTHSVC="/usr/lib/smbsrv/dtrace/smbd-authsvc.d"
KSTAT="dtrace/smb_kstat.d"
TASKQ="dtrace/smb_taskq_wait.d"
SESSIONS="dtrace/smb_sessions.sh"

DATE=$(date +%Y-%m-%d:%H:%M:%S)
DIR="logs/${DATE}"
IFACE=$1
declare -a PIDS

# Gracefully exit
trap cleanup SIGINT

cleanup() {
    for p in "${PIDS[@]}"; do
        kill "${p}"
    done
    exit
}

background() {
    cmd=$1
    log=$2

    ${cmd} > "${DIR}/${log}" &
    PIDS=("${PIDS[@]}" "$!")
}

# Verify all the binaries exist
for i in ${SMBSRV} ${AUTHSVC} ${KSTAT} ${TASKQ} ${SESSIONS}; do
    command -v $i &>/dev/null
    if [ $? -ne 0 ]; then
        echo "[ERROR] ${i} not found"
        exit 1
    fi
done

# Verify interface is defined
if [ $# -ne 1 ]; then
    echo "Usage"
    echo -e "\t$0 interface"
    exit 1
fi

# Verify interface exists
dladm show-link | grep "^${IFACE} " > /dev/null
if [ $? -ne 0 ]; then
    echo "[ERROR] ${IFACE} does not exist"
    exit 1
fi

# Make log directory
mkdir -p "${DIR}"

echo ""
echo "Ctrl-C to stop monitoring..."
echo ""

# Capture network traffic on the client interface
snoop -q -d "${IFACE}" -o "${DIR}/${IFACE}.snoop" not port 22 &
PIDS=("${PIDS[@]}" "$!")

# Monitor smbsrv internals
# ${SMBSRV} -o ${DIR}/smbsrv.out &
# PIDS=("${PIDS[@]}" "$!")

# Monitor authsvc internals
# ${AUTHSVC} -p `pgrep smbd` -o ${DIR}/smbd-authsvc.out &
# PIDS=("${PIDS[@]}" "$!")

# Monitor active connections
background "${SESSIONS}" "smb-sessions.out"

# Tail smb server logs
background "tail -f /var/svc/log/network-smb-server:default.log" "network-smb-server.out"

# Monitor smb statistics using smbstat
background "smbstat -rzu 1" "smbstat-rzu-1.out"

# Monitor taskq times
background "${TASKQ}" "smb-taskq-wait.out"

# Monitor SMB kstats
background "${KSTAT}" "smb-kstat.out"

# Loop
while true; do
    read x
done
