const generateClass = require('eth-contract-class').default;

const factoryArtifact = require('./dist/contracts/LPPMilestoneFactory.json');
const bridgedMilestoneArtifact = require('./dist/contracts/BridgedMilestone.json');
const lpMilestoneArtifact = require('./dist/contracts/LPMilestone.json');

module.exports = {
  LPMilestone: generateClass(lpMilestoneArtifact.abiDefinition, lpMilestoneArtifact.code),
  BridgedMilestone: generateClass(
    bridgedMilestoneArtifact.abiDefinition,
    bridgedMilestoneArtifact.code,
  ),
  MilestoneFactory: generateClass(factoryArtifact.abiDefinition, factoryArtifact.code),
};
