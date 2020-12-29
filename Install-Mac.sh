xcode-select --install

ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

brew cask install virtualbox
brew cask install vagrant
brew cask install ansible
vagrrant --version
ansible --version