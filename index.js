const generateClass = require('eth-contract-class').default;

const factoryArtifact = require('./build/MilestoneFactory.json');
const bridgedMilestoneArtifact = require('./build/BridgedMilestone.json');
const lpMilestoneArtifact = require('./build/LPMilestone.json');

module.exports = {
  LPMilestone: generateClass(lpMilestoneArtifact.compilerOutput.abi, lpMilestoneArtifact.compilerOutput.evm.bytecode.object),
  BridgedMilestone: generateClass(
    bridgedMilestoneArtifact.compilerOutput.abi,
    bridgedMilestoneArtifact.compilerOutput.evm.bytecode.object,
  ),
  MilestoneFactory: generateClass(factoryArtifact.compilerOutput.abi, factoryArtifact.compilerOutput.evm.bytecode.object),
};
