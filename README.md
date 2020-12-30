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

![Diagram](https://github.com/okutkan/K8s-Vagrant-Jenkins-Nexus/raw/main/k8-Vagrant.svg)

[open in new windows](https://viewer.diagrams.net/?highlight=0000ff&edit=_blank&layers=1&nav=1&title=k8-Vagrant.svg#R7V1bd6LIFv41edQFVRTCY2LiObMm3Z2Z9PScfuqFUFEmCA5gYvrXTxUWCFQpoMXFOfZydXRzUfb%2B6tu3oriB09X2P6G1Xn4KHOzdAMXZ3sD7GwA0c6KRP1TysZNAqDHJInSdnUzdC57dn5gJFSbduA6OCjvGQeDF7rootAPfx3ZckFlhGLwXd3sJvOK3rq0F5gTPtuXx0j9dJ17upAZS9vL%2FYnexTL9ZVdiWlZXuzATR0nKC95wIPtzAaRgE8e7dajvFHtVeqpfdcbMDW7MfFmI%2FrnPAH3%2B%2F%2F3yM3eVDuPjyrK%2F%2F%2Fn77mzZiZ3mzvA27YPZj449UA2Gw8R1MT6LcwLv3pRvj57Vl063vxOhEtoxXHvmkkrdRHAaveBp4QZgcDZXkX7Yl1SEkkhfX83J7viT%2FqDzwYwYEjR7JfiIOY7w9eO1qplGCRRyscBx%2BkF3YASMEmRUYDkdAY4L3vVVVw2TCZd6kMLWgxbC0yM6%2FVzd5wzQu1v7r968LNUA%2FzG%2FGx%2Fdf54EdfCU%2FQqlW%2F4Lof33geoVaYSPBmqdnUI6qJgNsqhnVEGgmG48FzWRS6ZqpgcsKJFrRescHL%2B6WoveO1%2BFxm5Q1y2uwTwWBagURwlnTt%2B4q4bi8cujFuYTkbj134RNZHKxz0kdrjr2nIHJjN6Bb50EcByuyg0c33Fn26yIhBdHgTb7sNtW9IjIE%2Bz33yzimJH5LFQFmtuODsUvA%2B%2BISugnHNvlGMHOs2CJ%2FqDyif4NoNBkl1ziiegxGG3eUblSBQf7%2FRMV%2F%2FPLjmxvGG8u7C7bjtb9o1fi6wPR6W4aHnOH3V8pBgFxEfIyg%2FcDHJSZmIoshwyYKw6EAMivXcejXCD1C0WfIVz7bOilSF%2BCJSxOYpjU6n9QYlAfovJlCGpP8BBU1pQu8H5wIdJX5TfnK4oF8XuhRU6mZkRoNcYi6VY5WrZxKtq7ke26MV5JDEtDdPcwA3Zm5l9V2QWP%2FsfVzE%2BLx246Mfqwse%2Bkmx7dqF10XUC8aqwbKvdoyEuKM9JkkQNQ1K98%2BXTYXN7AG22qCsVbgGFUfA1PPvTQ%2BrFTQWFdy%2F1TemhCMkQlyr7asqcsl74MabEzepdRFEJ5DUfCptefnJnVVdTjJO5woEu3EFqGOsCFi9bP13aNGDcngO18Z4hBLlBuK4gaotKYqk1PVU%2BBER2IHtTp2KKF0rjrOiyJCqapMoNnEqxkHDHE8mxSpVG0tpUiNegx9OWU5VrQsBmVRUbElbQJjgh6ASJsZG6wD14%2BTy0J35KWMFYU416ky1iH9c4PI3tNkg5qIQUlqCqXJKcp7mgdOPEmOJtsFJ1FLMppoFvYlLz4get3Mcehjop4kr6WXGf6SvLlfB458ALGtenHEqvyIFcWyWltRkiG7xCgIkDhgzWbMmWRY3cdb%2BRLkGocuuUwc0q9z%2FQURg1YG97ZoDGYbU8CmIuO0V0Yy%2BJT1%2BSOK8YrInnH45tqYp9ZhRLIF07ZmMYgKFstGVyGK7bLIYNTIm69kLZOsfZLUnRt31WWE3tmaLzx8Ti5fGfEwGwYP5NpFKpKQLxw0lVE0FeDzWVEhuD0i4MsP0yx1AsrvGz8mvk1qXGwBRQFIRA566nCpNUSk0ZpVzCJBi7tXoiHUml1kFxKk5XJmDV8mUlV7iQdfSPiV8LCHY3khIk3a5paKhT5NUfSH29n5sDXqw7Y%2FZdeoMVwDB5mBw2seyzIxxLaWmY8bzVDkj7SW8FW7KFhPHfKaX6WEGEJBjCXqE6LWsi7ec5%2FHd3U9ySkk1bFqajjPf1vj6ySrdBnRqHxS8GpEo5UVEe2NBtvqOjUxaErD1QU3VUjErU0Nkt1MaImIEa8oTaQorb1JVLJrk3V920ldga6VU4OKr%2FGizHhxR6itYkg4jaU1BPGtuumXz19%2F%2F%2FJIhE%2BPt58fBuo55JtgW1R16irM8cSEqgI1zQATlGYAec8hLCkZ42RvoOiGqSOk6i0ZMC1%2B5wyEnQV%2BZh%2BDMF4Gi8C3vIe9tKTK%2FT6PAY29Epv%2BheP4g7lmaxMHRYvjrRv%2FL%2Ff%2BOz3VGLFP91t25uTDR%2FrBJ9dLDxoRltCMVLI7FGiTVLA%2FOvlUOPwpbQYxYRRbYXxL7yGgsPKsKHLtVDxzvRM5Pwo2oY2P7Jhak3zNAh87o8qGFzXJUfCF2LNi9y2%2FUxtRIu8vcGw7Rxxq8wIk8QvAtkVOw9HnOtLbHLulmRCi3l2n9RxYI3i5%2BmeZ%2FnkP5xbgBUrw4n1Bp40gqF8K9fdF05MLpWm%2BTkdn3IWB5yV9o5XlW4s0CpVE246FjRchbeu2gecNCu1n07aazkfpjbdBjbndV96Wydv2j1VXtC2CV7e8Da7o6hZdkU012BG%2BQDqtvDd8TS4lLshSwuzD7qgJqkgG%2BwoojAsNKPhyczIkNp7sKAJhw9FE3GOAOdS7TP6y%2B476y%2F5qTANs1G49pJLGVf4sMz6cKItus2%2BxfcWXISmd069auxF%2BkwzTF8PG4hrF3EAaalBfzGzcqMTbrXLBdTpqx%2FEGAa18%2FIijDQ32G2ykUL7cYENSrFFuZR%2BeyFa8xwHwIyqbDFfXMaQ2qIxfzJrxSzrrT178khxKtGh95HZgvLA%2F8xMV7LGul%2FwUYp9nNfdXFVUpIXz3E%2FZ4z67ljFl7J7t5aSvEGKWu1Si74aG%2F1QN4l37Eh8tr3J%2FUc%2B147YB0QsD%2F0RSqk8zS59IB6oGlA8ivvvilAxrnVpe%2BcgCqMZ2zSSomLxOrvHe749vctRql784XDsjMd4kLB6AaTeAm2JOgjKEuHKDxja8BLxyADoVvR9HX8cIBsEYYdk3%2B%2B1k4oAGAhrlwAALV4LrQhQOa22ZwCwcg3pX%2FmxcOaG6xwS0coNXIC69k3dPCAQfjrrqM0Ddba%2BKMlkjStXwHxwMn3h%2FU3FQDWzhA42uKl79wQHOrDG7hACS5pSsvlxvcwgEaP9f8MhcOQCe1eDueanBdOGDQCwc0wNAgFw4wTA5Og%2B%2FyJggsdHp1WNHqPeceI3H%2Ft06X9zBz8ehKAzVpnd6UOXru9E5KnVut2Lit3B%2BwtcpbbfSmPnYIowCcNtlB084eAlldZo9%2FYTkVQuFjZUBxrOQeH3MKzk21Js5V2TA%2FrzfO9wS%2BWcTn%2BHxw1PQZKgI2Ue%2FvpsISGdf7RQoWPd6nfgTVuAZDUp3S2i%2BCmQvCJ7e0Vzgza5Q1L%2B7JLVrlk1s8QkzRaE5Q6ER0%2FZsZDSdmbztcjlRgJE9pEdZd23ia1JmwKj0zSbikUJd32puXebdeXbbPigTVbH%2Bo8HCGF4A1vQAalhfo50aNfISc3XW%2FA4YBzc7ig1ukKNpJiHEM8sPhMcRUAiF9tI3ksJeLU7OSfjqDsVwy3GGbHbXHU9P4ufw9poI6iIeNXvDLKC29TShltZPiYdBo9u8QoC2PDAd2j5LCx8R9wKtmun9OuoN9p4QoIsnhqQvbDywf4uvqt37k0tr3WcXiupPwBdFpVp7pMhkCirgMUpkMqSfMySIf94%2B23fmE%2FROC4cM%2F)
