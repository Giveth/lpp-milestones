const generateClass = require('@giveth/eth-contract-class').default;

const factoryArtifact = require('./dist/contracts/MilestoneFactory.json');
const bridgedMilestoneArtifact = require('./dist/contracts/BridgedMilestone.json');
const lpMilestoneArtifact = require('./dist/contracts/LPMilestone.json');

module.exports = {
  LPMilestone: generateClass(lpMilestoneArtifact.compilerOutput.abi, lpMilestoneArtifact.compilerOutput.evm.bytecode.object),
  BridgedMilestone: generateClass(
    bridgedMilestoneArtifact.compilerOutput.abi,
    bridgedMilestoneArtifact.compilerOutput.evm.bytecode.object,
  ),
  MilestoneFactory: generateClass(factoryArtifact.compilerOutput.abi, factoryArtifact.compilerOutput.evm.bytecode.object),
};
