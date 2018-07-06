#!/usr/bin/expect
set timeout 10
set username [lindex $argv 0]
set password [lindex $argv 1]
set hostname [lindex $argv 2]
spawn ssh-keygen -t rsa
expect {
        "*file in which to save the key*" {
            send "\n\r"
            send_user "/root/.ssh\r"
            exp_continue
        "*Overwrite (y/n)*"{
            send "n\n\r"
        }
        }
        "*Enter passphrase*" {
            send "\n\r"
            exp_continue
        }
        "*Enter same passphrase again*" {
            send "\n\r"
            exp_continue
        }
}
spawn ssh-copy-id -i /root/.ssh/id_rsa.pub $username@$hostname
expect {
            #first connect, no public key in ~/.ssh/known_hosts
            "Are you sure you want to continue connecting (yes/no)?" {
            send "yes\r"
            expect "password:"
                send "$password\r"
            }
            #already has public key in ~/.ssh/known_hosts
            "password:" {
                send "$password\r"
            }
            "Now try logging into the machine" {
                #it has authorized, do nothing!
            }
        }
expect eof