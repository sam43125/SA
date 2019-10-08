#!/usr/local/bin/bash

MainMenu() {
    HEIGHT=25
    WIDTH=80
    CHOICE_HEIGHT=20
    local MENU="SYS INFO"

    local OPTIONS=(1 "CPU INFO"
                   2 "MEMORY INFO"
                   3 "NETWORK INFO"
                   4 "FILE BROWSER"
                   5 "CPU USAGE")

    CHOICE=$(dialog --clear \
                    --menu "$MENU" \
                    $HEIGHT $WIDTH $CHOICE_HEIGHT \
                    "${OPTIONS[@]}" \
                    2>&1 >/dev/tty)

    clear
    case $CHOICE in
            1)
                CPUInfoMsgBox
                ;;
            2)
                MemoryInfoGauge
                ;;
            3)
                NetworkInfoMenu
                ;;
            4)  
                FileBrowserMenu
                ;;
            5)
                CPULoadingGauge
                ;;
            *)
                return 0
                ;;
    esac
}

CPUInfoMsgBox() {
    local Model=`sysctl -n hw.model`
    local Machine=`sysctl -n hw.machine`
    local Core=`sysctl -n hw.ncpu`
    local TEXT="CPU INFO\n\
                CPU Model:   $Model\n\
                CPU Machine:  $Machine\n\
                CPU Core:   $Core"
    CHOICE=$(dialog --clear \
                    --msgbox "$TEXT" \
                    $HEIGHT $WIDTH \
                    2>&1 >/dev/tty)
    clear
    MainMenu
}

MemoryInfoGauge() {
    local Total=`sysctl -n hw.realmem`
    local Used=`sysctl -n hw.usermem`
    local Free=$(($Total - $Used))
    local Percentage=$(($Used * 100 / $Total))

    MemoryUnitHandler $Total
    Total=$MemoryUnitHandlerResult
    MemoryUnitHandler $Used
    Used=$MemoryUnitHandlerResult
    MemoryUnitHandler $Free
    Free=$MemoryUnitHandlerResult


    local TEXT="Memory Info and Usage\n\nTotal: $Total\nUsed: $Used\nFree: $Free"
    CHOICE=$(dialog --mixedgauge "$TEXT" $HEIGHT $WIDTH $Percentage 2>&1 >/dev/tty)
    read n
    MainMenu
}

MemoryUnitHandler() {
    local temp=0
    MemoryUnitHandlerResult=$1
    while (($(echo "$MemoryUnitHandlerResult > 1024.0" | bc -l) )); do
        MemoryUnitHandlerResult=$(bc <<< "scale=2;$MemoryUnitHandlerResult/1024")
        temp=$(($temp + 1))
    done
    case $temp in
            0)
                MemoryUnitHandlerResult+=" B"
                ;;
            1)
                MemoryUnitHandlerResult+=" KB"
                ;;
            2)
                MemoryUnitHandlerResult+=" MB"
                ;;
            3)
                MemoryUnitHandlerResult+=" GB"
                ;;
            4)  
                MemoryUnitHandlerResult+=" TB"
                ;;
            *)  ;;
    esac
}

NetworkInfoMenu() {
    local MENU="Network Interfaces"
    local temp=($(ifconfig | egrep '^\w+\: ' | cut -d' ' -f1 | tr -d ":"))
    local OPTIONS
    for i in `seq ${#temp[@]}`; do
        OPTIONS[i*2-2]="${temp[i-1]}"
        OPTIONS[i*2-1]="*"
    done

    CHOICE=$(dialog --clear \
                    --menu "$MENU" \
                    $HEIGHT $WIDTH $CHOICE_HEIGHT \
                    "${OPTIONS[@]}" \
                    2>&1 >/dev/tty)

    clear
    case $CHOICE in
        '') MainMenu ;;   
        *)  NetworkInfoMsgBox $CHOICE ;;
    esac
}

NetworkInfoMsgBox() {
    local IPv4=`ifconfig $1 | grep 'inet ' | cut -d ' ' -f2`
    local Netmask=`ifconfig $1 | grep 'inet ' | cut -d ' ' -f4`
    local MAC=`ifconfig $1 | grep 'hwaddr' | cut -d ' ' -f2`
    local TEXT="Interface Name: $1\n\nIPv4___: $IPv4\nNetmask: $Netmask\nMAC____: $MAC"
    CHOICE=$(dialog --clear \
                    --msgbox "$TEXT" \
                    $HEIGHT $WIDTH \
                    2>&1 >/dev/tty)
    clear
    NetworkInfoMenu
}

FileBrowserMenu() {
    local MENU="File Browser: "
    local Pwd=`pwd`
    MENU="$MENU$Pwd"

    local temp=($(ls -a))
    local OPTIONS
    for i in `seq ${#temp[@]}`; do
        OPTIONS[i*2-2]="${temp[i-1]}"
        OPTIONS[i*2-1]=`file -b --mime-type ${temp[i-1]}`
    done

    CHOICE=$(dialog --clear \
                    --menu "$MENU" \
                    $HEIGHT $WIDTH $CHOICE_HEIGHT \
                    "${OPTIONS[@]}" \
                    2>&1 >/dev/tty)

    local Type=`file -b --mime-type $CHOICE`

    clear
    case $Type in
            '')
                MainMenu
                ;;
            inode/directory)
                cd $CHOICE
                FileBrowserMenu
                ;;
            text/*)
                FileBrowserEditableMsgBox $CHOICE
                ;;
            *)
                FileBrowserUneditableMsgBox $CHOICE
                ;;
    esac
}

FileBrowserEditableMsgBox() {

    local FileInfo=`file -b $1`
    local FileSize=`du -h $1 | cut -f1`
    local TEXT="<File Name>: $1\n<File Info>: $FileInfo\n<File Size>: $FileSize"

    dialog --clear \
           --extra-button \
           --extra-label "Edit" \
           --msgbox "$TEXT" \
           $HEIGHT $WIDTH  \
           2>&1 >/dev/tty

    local CHOICE=$?
    clear
    case $CHOICE in
        0)
            FileBrowserMenu
            ;;
        3)
            ${EDITOR:=vi} $1
            FileBrowserEditableMsgBox $1
            ;;
        *)
            echo "ERROR" 1>&2
            exit
            ;;
    esac
}

FileBrowserUneditableMsgBox() {
    local FileInfo=`file -b $1`
    local FileSize=`du -h $1 | cut -f1`
    local TEXT="<File Name>: $1\n<File Info>: $FileInfo\n<File Size>: $FileSize"
    CHOICE=$(dialog --clear \
                    --msgbox "$TEXT" \
                    $HEIGHT $WIDTH \
                    2>&1 >/dev/tty)
    clear
    FileBrowserMenu
}

CPULoadingGauge() {
    local regex_floating="[0-9]+\.[0-9]+%"
    local ncores=`sysctl -n hw.ncpu`
    if [ $ncores = '1' ] ; then
        local delay=1
    else
        local delay=2
    fi
    local avg=`top -d$delay | grep 'CPU:' | tail -n1 | egrep -o "$regex_floating system" | cut -d ' ' -f1`
    local temps=`top -P -d$delay | egrep 'CPU( [0-9]+|:)'`
    local cores
    local old_IFS=$IFS
    IFS=$'\n'
    for core in $temps; do
        local id=`echo -e $core | egrep -o '(CPU:|CPU [0-9]+:)'`
        local user=`echo -e $core | egrep -o "$regex_floating user" | cut -d ' ' -f1`
        local sys=`echo -e $core | egrep -o "$regex_floating system" | cut -d ' ' -f1`
        local idle=`echo -e $core | egrep -o "$regex_floating idle" | cut -d ' ' -f1`
        cores="$cores\n$id USER: $user SYST: $sys IDLE: $idle"
    done
    IFS=$old_IFS

    local TEXT="CPU Loading\n$cores"
    CHOICE=$(dialog --mixedgauge "$TEXT" $HEIGHT $WIDTH ${avg%%\.*} 2>&1 >/dev/tty)
    read n
    MainMenu
}

MainMenu