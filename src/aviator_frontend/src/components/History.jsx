import React from 'react';

const History = ({ rounds }) => {
  return (
    <div className="history">
      <h3>Previous Rounds</h3>
      <div classNameName="rounds-list">
        {rounds.map((round, index) => (
          <span key={index} className="round-item" style={{ color: round.crashed ? '#ff5555' : '#4caf50' }}>
            {round.multiplier.toFixed(2)}x
          </span>
        ))}
      </div>
    </div>
  );
};

export default History;
