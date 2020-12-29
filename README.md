# K8s-Vagrant
Kubernetes Setup Using Ansible and Vagrant

This repo is based on the Kubernetes.io blog post about setting up Kubernetes cluster using ansible and vagrant.

For more details see [blog post](https://kubernetes.io/blog/2019/03/15/kubernetes-setup-using-ansible-and-vagrant/)


## Prerequisites

- Vagrant should be installed on your machine. Installation binaries can be found  [here](https://www.vagrantup.com/downloads.html "here")

- Oracle VirtualBox can be used as a Vagrant provider or make use of similar providers as described in Vagrant's official [documentation.](https://www.vagrantup.com/docs/providers/)

- Ansible should be installed in your machine. Refer to the [Ansible installation guide](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) for platform specific installation


## Getting started

- run `Install-Linux.sh` or `Install-Mac.sh` depending on your operating system

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