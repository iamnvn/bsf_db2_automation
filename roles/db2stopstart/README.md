db2 stop or start instance/databases:
====================================
  - This playbook will be used to stop or start db2 luw instance and databases.
  - This playbook able to handle Stand-Alone, HADR 2,3 or 4 servers.

Requirements:
------------
  - We must prepared with inventory file as shown in examples.
  - We must have root/sudo access to run this playbook.
  - Declare Variables to match with our Environment.
 Inventory Examples:
    [db2hadr]
    172.20.10.2 ansible_user=db2inst1
    172.20.10.4 ansible_user=db2inst2

            (OR)

    [fptest]
    dvltestdb1
    dvltestdb2
    dvltestdb3

    [fptest:vars]
    ansible_user = db2inst1

Play Variables:
--------------
  - Change Variables to match our Environment in vars/vars_db2.yaml
    Example:
      targethost: db2test    #Group name(inventory group name) of hosts we want to run Fix pack install.
      tgtdir: /tmp          #Target server path to use ansible controller.



Examples for run Playbook:
-------------------------
ansible-playbook start_stop_db2.yaml -i inventory
ansible-playbook start_stop_db2.yaml -i inventory --skip-tags info
ansible-playbook start_stop_db2.yaml -i inventory --tags createdirs / --list-tags

Author Information
------------------
  # Date: Feb 14, 2022
  # Written by: Naveen Chintada
