# K8s-Vagrant-Ansible

Kubernetes Setup Using Ansible and Vagrant

This repo is based on the Kubernetes.io blog post about setting up Kubernetes cluster using ansible and vagrant.

For more details see [blog post](https://kubernetes.io/blog/2019/03/15/kubernetes-setup-using-ansible-and-vagrant/)

## Prerequisites

- Vagrant should be installed on your machine. Installation binaries can be found  [here](https://www.vagrantup.com/downloads.html "here")

- Oracle VirtualBox can be used as a Vagrant provider or make use of similar providers as described in Vagrant's official [documentation.](https://www.vagrantup.com/docs/providers/)

- Ansible should be installed in your machine. Refer to the [Ansible installation guide](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) for platform specific installation

## Getting started

- run `Install-Linux.sh` or `Install-Mac.sh` depending on your operating system
- After installations steps run `up.sh` on your terminal

## Setup Overview

### Step 1: Vagrantfile

- The value of IMAGE_NAME can be changed to reflect desired `vagrant base image`.
- The value of N denotes the number of nodes present in the cluster, it can be modified accordingly. In the below example, we are setting the value of N as 2.

```bash
IMAGE_NAME = "ubuntu/focal64"
N = 2

Vagrant.configure("2") do |config|
    config.ssh.insert_key = false

    config.vm.provider "virtualbox" do |v|
        v.memory = 1024
        v.cpus = 2
    end
      
    config.vm.define "k8s-master" do |master|
        master.vm.box = IMAGE_NAME
        master.vm.network "private_network", ip: "192.168.50.10"
        master.vm.hostname = "k8s-master"
        master.vm.provision "ansible" do |ansible|
            ansible.playbook = "kubernetes-setup/master-playbook.yml"
            ansible.extra_vars = {
                node_ip: "192.168.50.10",
            }
        end
    end

    (1..N).each do |i|
        config.vm.define "node-#{i}" do |node|
            node.vm.box = IMAGE_NAME
            node.vm.network "private_network", ip: "192.168.50.#{i + 10}"
            node.vm.hostname = "node-#{i}"
            node.vm.provision "ansible" do |ansible|
                ansible.playbook = "kubernetes-setup/node-playbook.yml"
                ansible.extra_vars = {
                    node_ip: "192.168.50.#{i + 10}",
                }
            end
        end
    end
```

### Step 2: Ansible playbook for Kubernetes master

- Created two files named `master-playbook.yml` and `node-playbook.ym`l in the directory `kubernetes-setup`. These files contains master and notes respectively.

#### Step 2.1: Docker and its dependent components

- Following packages installed, and then a user named `“vagrant”` added to the `“docker”` group.
  - docker-ce
  - docker-ce-cli
  - containerd.io

 ```YAML
---
- hosts: all
  become: true
  tasks:
  - name: Install packages that allow apt to be used over HTTPS
    apt:
      name: "{{ packages }}"
      state: present
      update_cache: yes
    vars:
      packages:
      - apt-transport-https
      - ca-certificates
      - curl
      - gnupg-agent
      - software-properties-common

  - name: Add an apt signing key for Docker
    apt_key:
      url: https://download.docker.com/linux/ubuntu/gpg
      state: present

  - name: Add apt repository for stable version
    apt_repository:
      repo: deb [arch=amd64] https://download.docker.com/linux/ubuntu xenial stable
      state: present

  - name: Install docker and its dependecies
    apt: 
      name: "{{ packages }}"
      state: present
      update_cache: yes
    vars:
      packages:
      - docker-ce 
      - docker-ce-cli 
      - containerd.io
    notify:
      - docker status

  - name: Add vagrant user to docker group
    user:
      name: vagrant
      group: docker
 ```

#### Step 2.2: Disabling swap

-Kubelet will not start if the system has swap enabled, so we are disabling swap using the below code

```YAML
  - name: Remove swapfile from /etc/fstab
    mount:
      name: "{{ item }}"
      fstype: swap
      state: absent
    with_items:
      - swap
      - none

  - name: Disable swap
    command: swapoff -a
    when: ansible_swaptotal_mb > 0
```

#### Step 2.3: Install kubelet, kubeadm and kubectl

-Installing kubelet, kubeadm and kubectl using the below code

```YAML
  - name: Add an apt signing key for Kubernetes
    apt_key:
      url: https://packages.cloud.google.com/apt/doc/apt-key.gpg
      state: present

  - name: Adding apt repository for Kubernetes
    apt_repository:
      repo: deb https://apt.kubernetes.io/ kubernetes-xenial main
      state: present
      filename: kubernetes.list

  - name: Install Kubernetes binaries
    apt: 
      name: "{{ packages }}"
      state: present
      update_cache: yes
    vars:
      packages:
        - kubelet 
        - kubeadm 
        - kubectl

  - name: Configure node ip
    lineinfile:
      path: /etc/default/kubelet
      line: KUBELET_EXTRA_ARGS=--node-ip={{ node_ip }}

  - name: Restart kubelet
    service:
      name: kubelet
      daemon_reload: yes
      state: restarted
```

- Initialize the Kubernetes cluster with kubeadm using the below code (applicable only on master node)

```YAML
- name: Initialize the Kubernetes cluster using kubeadm
    command: kubeadm init --apiserver-advertise-address="192.168.50.10" --apiserver-cert-extra-sans="192.168.50.10"  --node-name k8s-master --pod-network-cidr=192.168.0.0/16
```

#### Step 2.4: Setup the kube config file

- Setup the kube config file for the vagrant user to access the Kubernetes cluster using the below code

```YAML
  - name: Setup kubeconfig for vagrant user
    command: "{{ item }}"
    with_items:
     - mkdir -p /home/vagrant/.kube
     - cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
     - chown vagrant:vagrant /home/vagrant/.kube/config
```

#### Step 2.5: Setup the container networking

- Setup the container networking provider and the network policy engine using the below code.

```YAML
  - name: Install calico pod network
    become: false
    command: kubectl create -f https://docs.projectcalico.org/v3.4/getting-started/kubernetes/installation/hosted/calico.yaml
```

#### Step 2.6: Generate kube join command

- Generate kube join command for joining the node to the Kubernetes cluster and store the command in the file named join-command.

```YAML
  - name: Generate join command
    command: kubeadm token create --print-join-command
    register: join_command

  - name: Copy join command to local file
    local_action: copy content="{{ join_command.stdout_lines[0] }}" dest="./join-command"
```

#### Step 2.7: Setup a handler

-Setup a handler for checking Docker daemon using the below code.

```YAML
  handlers:
    - name: docker status
      service: name=docker state=started
```

### Step 3: Ansible playbook for Kubernetes node

- Create a file named `node-playbook.yml` in the directory `kubernetes-setup`.
- Added code from  steps 2.1 -2.3 to `node-playbook.yml`.
- Add the code below into `node-playbook.yml`.
- Add the code from step 2.7 to finish this playbook

```YAML
  - name: Copy the join command to server location
    copy: src=join-command dest=/tmp/join-command.sh mode=0777

  - name: Join the node to cluster
    command: sh /tmp/join-command.sh
```

### Step 4: Shell script to startup vagrant

```BASH
 vagrant up
 ```

## How to access Kunernetes cluster and nodes

-Upon completion of all the above steps, the Kubernetes cluster should be up and running. We can login to the master or worker nodes using Vagrant as follows:

````BASH
$ ## Accessing master
$ vagrant ssh k8s-master
vagrant@k8s-master:~$ kubectl get nodes
NAME         STATUS   ROLES    AGE     VERSION
k8s-master   Ready    master   18m     v1.13.3
node-1       Ready    <none>   12m     v1.13.3
node-2       Ready    <none>   6m22s   v1.13.3

$ ## Accessing nodes
$ vagrant ssh node-1
$ vagrant ssh node-2
````
