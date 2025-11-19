import React, { useState, useEffect } from 'react';
import GameDisplay from './components/GameDisplay';
import Controls from './components/Controls';
import History from './components/History';

function App() {
  const [multiplier, setMultiplier] = useState(1.00);
  const [gameState, setGameState] = useState('waiting'); // waiting, playing, crashed
  const [rounds, setRounds] = useState([]);

  useEffect(() => {
    let gameInterval;
    let crashTimeout;

    if (gameState === 'playing') {
      let currentMultiplier = 1.00;
      const crashPoint = Math.random() * 9 + 1.01; // Random crash between 1.01x and 10.00x

      gameInterval = setInterval(() => {
        currentMultiplier += 0.01;
        setMultiplier(currentMultiplier);
      }, 100); // Update every 100ms

      crashTimeout = setTimeout(() => {
        clearInterval(gameInterval);
        setGameState('crashed');
        setRounds(prevRounds => [{ multiplier: currentMultiplier, crashed: true }, ...prevRounds]);
        setTimeout(() => { // Reset after a short delay
          setGameState('waiting');
          setMultiplier(1.00);
        }, 3000);
      }, crashPoint * 1000); // Crash at the calculated point
    } else if (gameState === 'waiting') {
      // Automatically start a new round after a short delay
      setTimeout(() => {
        setGameState('playing');
      }, 2000);
    }

    return () => {
      clearInterval(gameInterval);
      clearTimeout(crashTimeout);
    };
  }, [gameState]);

  return (
    <div className="container">
      <h1>Aviator Game</h1>
      <div className="game-area">
        <GameDisplay multiplier={multiplier} gameState={gameState} />
        <Controls />
      </div>
      <History rounds={rounds} />
    </div>
  );
}

export default App;
