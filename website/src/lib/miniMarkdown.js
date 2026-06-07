import React from 'react';

// Minimal inline markdown for course/tour prose: **bold**, *italic*, `code`.
// Not a full markdown engine — just the subset the authored content uses.
export function renderInline(text) {
  const nodes = [];
  const regex = /(\*\*([^*]+)\*\*|`([^`]+)`|\*([^*]+)\*)/g;
  let lastIndex = 0;
  let key = 0;
  let match;
  while ((match = regex.exec(text)) !== null) {
    if (match.index > lastIndex) {
      nodes.push(text.slice(lastIndex, match.index));
    }
    if (match[2] !== undefined) {
      nodes.push(<strong key={key++}>{match[2]}</strong>);
    } else if (match[3] !== undefined) {
      nodes.push(<code key={key++}>{match[3]}</code>);
    } else if (match[4] !== undefined) {
      nodes.push(<em key={key++}>{match[4]}</em>);
    }
    lastIndex = match.index + match[0].length;
  }
  if (lastIndex < text.length) {
    nodes.push(text.slice(lastIndex));
  }
  return nodes;
}

export function Markdown({text}) {
  return (
    <>
      {text.split('\n\n').map((para, index) => (
        <p key={index}>{renderInline(para)}</p>
      ))}
    </>
  );
}
