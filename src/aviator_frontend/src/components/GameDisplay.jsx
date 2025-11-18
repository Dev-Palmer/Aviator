import React from 'react';

const GameDisplay = ({ multiplier, gameState }) => {
  const color = gameState === 'crashed' ? '#ff5555' : '#4caf50';
  return (
    <div className="game-display" style={{ color }}>
      <h2>{multiplier.toFixed(2)}x</h2>
      <p>{gameState}</p>
    </div>
  );
};

export default GameDisplay;
