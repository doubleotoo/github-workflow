#!/bin/bash

gem build github_flow.gemspec
gem install ./github_flow-0.0.0.gem

# pushd gems/git-pulls
# gem build ./git-pulls.gemspec
# gem install ./git-pulls-0.3.4.gem
# popd

