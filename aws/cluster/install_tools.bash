#!/bin/bash
# versions of kubernetes in kubectl and eksctl (create_cluster.bash script) manifest must match
export KUBERNETES_VERSION="1.26.2"
mkdir -p install_dir
cd install_dir || exit 1
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
sudo ./get_helm.sh
rm get_helm.sh

sudo pip uninstall -y awscli
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install --update
rm awscliv2.zip
rm -r aws/
# . ~/.bash_profile

# install eksctl
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH
curl -sLO "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
# (Optional) Verify checksum
curl -sL "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_checksums.txt" | grep $PLATFORM | sha256sum --check
tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
sudo mv /tmp/eksctl /usr/local/bin
eksctl version || ( echo "eksctl not found" && exit 1 )

# install kubectl
sudo curl --silent --location -o /usr/local/bin/kubectl "https://s3.us-west-2.amazonaws.com/amazon-eks/$KUBERNETES_VERSION/2023-03-17/bin/linux/amd64/kubectl"
sudo chmod +x /usr/local/bin/kubectl
kubectl version --client=true || ( echo "kubectl not found" && exit 1 )

# install additional tools
sudo apt -y install jq gettext bash-completion moreutils

# enable bash completion
kubectl completion bash >>  ~/.bash_completion
eksctl completion bash >> ~/.bash_completion
. ~/.bash_completion

# install yq
sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && sudo chmod +x /usr/bin/yq

# make sure all binaries are in the path
for command in kubectl jq envsubst aws eksctl kubectl helm
  do
    which $command &>/dev/null && echo "$command in path" || ( echo "$command NOT FOUND" && exit 1 )
  done

echo 'Prerequisites installed successfully.'
cd ..
rmdir install_dir

